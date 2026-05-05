require "sqlite3"
require "json"
require "os"

class Paradoxical::Game
  include Paradoxical::FileParser

  attr_reader :game_module, :name, :executable, :steam_id, :root, :user_directory
  attr_reader :mod, :playset

  # Build a Game from a `Paradoxical::Games::*` module — all per-game
  # constants (NAME, STEAM_ID, NATIVE_PLATFORMS, HAS_GAME_SUBDIR,
  # LAUNCHER_FORMAT, etc.) flow from there. `root:` and
  # `user_directory:` override the default install / user paths for
  # advanced callers.
  #
  # The constructor wires up everything a mod script expects:
  # - install + user dirs (with userdir.txt fallback)
  # - launcher dispatch (Sqlite / Json / Legacy stub)
  # - per-version corrections from the game module's CORRECTIONS hash
  def initialize game_module, root: nil, user_directory: nil
    @game_module = game_module
    @name = game_module::NAME
    @steam_id = game_module::STEAM_ID
    @executable = Paradoxical::Games.executable_for(game_module)
    @file_cache = {}

    @root = Pathname.new(root || default_root)
    @user_directory = Pathname.new(user_directory || resolve_user_directory)

    case game_module::LAUNCHER_FORMAT
    when :sqlite then extend(SqliteConfig)
    when :json   then extend(JsonConfig)
    when :legacy then extend(LegacyConfig)
    else raise ArgumentError, "unknown LAUNCHER_FORMAT for #{game_module}: #{game_module::LAUNCHER_FORMAT.inspect}"
    end

    register_corrections
  end

  private

  def default_root
    base = File.join(steamapps_dir, "common", @game_module::NAME)
    @game_module::HAS_GAME_SUBDIR ? File.join(base, "game") : base
  end

  def resolve_user_directory
    userdir_txt = @root.join("userdir.txt")
    return File.read(userdir_txt).chomp if userdir_txt.file?

    default_user_directory(@game_module::NAME)
  end

  def register_corrections
    installed = @game_module.installed_version(self)
    Paradoxical::Games::Corrections.resolve(@game_module::CORRECTIONS, installed).each do |path, block|
      add_correction(path, &block)
    end
  end

  public

  def mods
    _mods.dup
  end

  def enabled_mods
    _enabled_mods.dup
  end

  def mod_named name
    mods.find do |mod| mod.name.include? name	end
  end

  def mod= mod
    @mod = mod
    @enabled_mods = nil
    @mod
  end

  def playset= playset
    @playset = playset
    @enabled_mods = nil
    @playset
  end

  def is? name
    name == self.executable
  end

  def exists? relative_path, mod: false
    return super relative_path if mod == false

    return mod.exists? relative_path unless mod.nil?

    return true unless mod_for_path(relative_path).nil?

    super relative_path
  end

  def glob relative_path
    [super, *_enabled_mods.map do |mod| mod.glob relative_path end].flatten.uniq.sort
  end

  def read relative_path, mod: false, encoding: nil
    mod ||= mod_for_path relative_path, mod: mod unless mod == false

    return super relative_path, encoding: encoding unless mod.present?

    mod.read relative_path, encoding: encoding
  end

  def parse_file relative_path, mod: nil, mutex: nil, ignore_cache: false, encoding: nil
    mod ||= mod_for_path relative_path, mod: mod unless mod == false

    return super relative_path, mutex: mutex, ignore_cache: ignore_cache, encoding: encoding unless mod.present?

    mod.parse_file relative_path, mutex: mutex, ignore_cache: ignore_cache, encoding: encoding
  end

  def parse_files *files, mod: nil, encoding: nil
    mutex = Mutex.new

    results = files.flatten.map do |relative_path|
      _mod = mod_for_path relative_path, mod: mod

      Thread.new do
        document = parse_file relative_path, mod: _mod, mutex: mutex, encoding: encoding

        Thread.current[:document] = document
      end
    end.map do |thread| thread.join[:document] end

    results.count > 1 ? results : results.first
  end

  private

  def mod_for_path relative_path, mod: nil
    return mod unless mod.nil?

    _enabled_mods.reverse_each.find do |mod| mod.exists? relative_path end
  end
end

class Paradoxical::Game
  private

  def default_user_directory name
    File.expand_path(
      File.join(
        "~",
        *(OS.linux? ? [".local", "share"] : ["Documents"]),
        "Paradox Interactive",
        name,
      )
    )
  end

  def steamapps_dir
    @steamapps_dir ||= File.expand_path(
      File.join(
        *(
          OS.linux? ? ["~", ".local", "share"] :
          OS.mac?   ? ["~", "Library", "Application Support"] :
                      ["C", "Program Files (x86)"]
        ),
        "Steam",
        "steamapps",
      )
    )
  end
end

# Stub mod-loading for games whose launcher we haven't ported to —
# currently CK2, which predates both the SqliteConfig and JsonConfig
# launchers. Returns empty lists so parser-only usage works
# transparently (parse_file falls through to the bare FileParser
# path); `paradoxical!` with `mod:`/`playset:` set on a `:legacy`
# game silently no-ops on selection, which is a known gap until/
# unless someone needs it.
module LegacyConfig
  def _mods
    @mods ||= []
  end

  def _enabled_mods
    @enabled_mods ||= []
  end
end

module SqliteConfig
  def db
    @db ||= SQLite3::Database.new user_directory.join("launcher-v2.sqlite")
  end

  def _mods
    # Smoke / parser-only callers can hand Game a user_directory
    # that doesn't have the launcher SQLite. Return an empty mod
    # list so `mod_for_path` resolves to nil and parse_file falls
    # through to the bare FileParser path.
    return @mods ||= [] unless user_directory.join("launcher-v2.sqlite").file?

    @mods ||= db.execute("SELECT id, gameRegistryId FROM mods;").map do |(id, gameRegistryId)|
      Paradoxical::Mod.new self, id, user_directory.join(gameRegistryId)
    end
  end

  def _enabled_mods
    @enabled_mods ||= begin
      enabled_mods = if @playset.present? then
                       sql = <<~SQL
                         SELECT m.id FROM mods m
                         JOIN playsets_mods pm ON pm.modId = m.id
                         JOIN playsets p ON pm.playsetId = p.id
                         WHERE pm.enabled AND p.name = '#{@playset}'
                         ORDER BY pm.position ASC;
                       SQL
                       db
                         .execute(sql)
                         .map do |(id)| _mods.find do |mod| mod.id == id end end
                     else
                       _mods.dup
                     end

      enabled_mods.delete_if do |other| other.id == @mod.id end if @mod.present?

      enabled_mods
    end
  end
end

module JsonConfig
  def _mods
    @mods ||= (
      Dir[File.join(steamapps_dir, "common", "workshop", "content", steam_id.to_s, "*", ".metadata", "metadata.json")] +
      Dir[File.join(user_directory, "mod", "*", ".metadata", "metadata.json")]
    ).map do |metadata_path|
      path = File.expand_path File.join(metadata_path, "..", "..")
      steam_id = File.basename path
      metadata = JSON.parse File.read(metadata_path, encoding: "bom|utf-8")
      name = metadata["name"]
      id = metadata["id"]
      Paradoxical::Mod.new self, id, path, name: name, steam_id: steam_id
    end
  end

  def _enabled_mods
    @enabled_mods ||= begin
      enabled_mods = if @playset.present? then
                       playsets = JSON.parse(File.read(File.join(user_directory, "playsets.json"),
                                                       encoding: "bom|utf-8"))["playsets"]
                       playset = playsets.find do |p| p["name"] === self.playset end
                       _mods.filter do |mod|
                         playset["orderedListMods"].any? do |entry|
                           entry["isEnabled"] and File.basename(entry["path"]) == File.basename(mod.path)
                         end
                       end
                     else
                       _mods.dup
                     end

      enabled_mods.delete_if do |other| other.name == @mod.name end if @mod.present?

      enabled_mods
    end
  end
end
