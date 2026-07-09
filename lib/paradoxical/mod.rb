require "json"

class Paradoxical::Mod
  include Paradoxical::FileParser

  attr_reader :game, :id, :path, :corrections, :name, :steam_id, :written_paths

  def initialize game, id, path, name: nil, steam_id: nil
    @game = game
    @id = id
    @path = Pathname.new path
    @name = name
    @steam_id = steam_id

    @file_cache = {}
    @config = {}
    @corrections = {}
    # Absolute paths written (or explicitly protected) during this run. Populated by
    # `write`, `install_asset`, and `mark_written`; consumed by `cleanup_orphans` to tell
    # current outputs from stale ones.
    @written_paths = Set.new

    # SqliteConfig hands us the path to a `.mod` descriptor (a
    # paradox-script document) — parse it and stash properties.
    # JsonConfig hands us the mod's root dir; metadata lives in
    # `.metadata/metadata.json` per mod. Discriminate on the active
    # game's launcher format rather than re-deriving it.
    case game.game_module::LAUNCHER_FORMAT
    when :sqlite
      parse_file(path).properties.each do |p|
        @config[p.key] = p.value
      end
    when :json
      meta = JSON.parse(File.read(File.join(path, ".metadata", "metadata.json"), encoding: "bom|utf-8"))
      @config["name"] = meta["name"]
      @config["path"] = path
      @config["supported_version"] = meta["supported_game_version"]
      @config["archive"] = false
    else
      raise ArgumentError,
            "Mod construction not supported for #{game.game_module::LAUNCHER_FORMAT.inspect} launcher format"
    end
  end

  %w{name path supported_version remote_file_id archive}.each do |key|
    define_method key do
      @config[key]
    end
  end

  def archive?
    @config["archive"].present?
  end

  def enabled?
    game.enabled_mods.include? self
  end

  def exists? relative_path
    return super unless archive?

    result = nil

    Zip::File.open(archive) do |zip_file|
      result = zip_file.glob(relative_path.to_s).first.present?
    end

    result
  end

  def glob relative_path
    return super unless archive?

    result = nil

    Zip::File.open(archive) do |zip_file|
      result = zip_file.glob(relative_path.to_s).map(&:name)
    end

    result
  end

  def read relative_path, encoding: nil
    return super unless archive?

    result = nil

    Zip::File.open(archive) do |zip_file|
      result = zip_file.glob(relative_path.to_s).first.get_input_stream.read
    end

    enforce_encoding! result, encoding: encoding, path: relative_path
  end

  def root
    Pathname.new(path.to_s.start_with?("/") ? path : File.join(game.user_directory, path))
  end

  def write file
    full_path = full_path_for file.path

    data = file.bom? ? "\xEF\xBB\xBF" : ""
    data << file.to_pdx

    data.encode! file.encoding unless file.encoding.nil?

    write_data full_path, data
  end

  # Copy a binary asset into the mod, skipping the copy when the deployed file is already
  # current. Unlike text output we don't byte-compare (assets can be large): mtime + size is
  # a cheap proxy — if the deployed file is at least as new as the source and the same size,
  # assume it's up to date. Copying in place (not delete + recreate) preserves the inode so
  # the game's file watch survives, and marks the destination as a current output so
  # `cleanup_orphans` spares it. Returns true if it copied, false if it skipped.
  def install_asset src, relative_dest
    dest = full_path_for relative_dest
    mark_written dest

    if File.exist?(dest) && File.size(dest) == File.size(src) && File.mtime(dest) >= File.mtime(src)
      return false
    end

    FileUtils.mkdir_p dest.dirname
    FileUtils.cp src, dest
    true
  end

  # Record an absolute path as a current output of this run so `cleanup_orphans` won't treat
  # it as stale. `write` and `install_asset` call this automatically; it's public so callers
  # can protect files they deploy by some other means. Accepts a relative or absolute path.
  def mark_written path
    written_paths << File.expand_path(full_path_for(path)).to_s
  end

  # Clear the recorded outputs. A fresh `ruby compile.rb` process gets an empty set for free
  # (new Mod per run), so a one-shot compile never needs this. It's for a long-lived Mod that
  # recompiles in-process (a watch daemon, tests): call it at the START of each build so a file
  # emitted last cycle but not this one is no longer protected and `cleanup_orphans` can reap
  # it. Reset at the start, not the end, so it also recovers cleanly if a prior build crashed.
  def reset_written_paths!
    written_paths.clear
  end

  # Delete files under the mod that this run did NOT write — the mod root is a pure build
  # output, so a file we no longer emit is stale. `within` limits the sweep to specific
  # relative subdirectories (a String or Array); nil sweeps the whole root. Empty directories
  # left behind are pruned. Returns the paths removed.
  #
  # This replaces wiping whole directories up front, which destroyed inodes (breaking the
  # game's inotify watches) and forced every generated file to be rewritten on every run.
  def cleanup_orphans within: nil
    bases = within ? Array(within).map { |dir| full_path_for dir } : [root]

    removed = []
    bases.each do |base|
      next unless File.directory? base

      Dir.glob(base.join("**", "*"), File::FNM_DOTMATCH).each do |path|
        next if File.directory? path
        next if written_paths.include? File.expand_path(path).to_s

        File.delete path
        removed << path
      end

      prune_empty_dirs base
    end

    removed
  end

  # Run a full build from a directory of generator scripts — the whole compile pipeline in one
  # call. Resets the output tracking (so repeated in-process builds stay correct), loads every
  # `**/*.rb` under `dir` (each emits files via the global `write` helper), mirrors static files
  # from `dir/<assets>/` into the mod, then reaps anything this run didn't produce. Returns the
  # orphan paths removed.
  #
  # Generators are `load`ed, not `require`d, so they re-run on every call — a long-lived watcher
  # that calls compile repeatedly regenerates everything each time instead of skipping already-
  # loaded files. (The tradeoff: a generator that defines top-level constants will warn on the
  # second load — harmless, and a non-issue for one-shot `ruby compile.rb` runs.)
  #
  # `without`  — extra script paths to skip when loading, relative to `dir` or absolute. The entry
  #             script (`$PROGRAM_NAME`) and anything already pulled in via require/require_relative
  #             (i.e. bootstraps like `setup.rb`, which must not re-run) are skipped automatically.
  #             Use it for a shared-constants file: keep it out of the sweep, then `require_relative`
  #             it from the generators that need it — that loads it exactly once and avoids the
  #             re-initialized-constant warnings a `load` on every compile would raise.
  # `sort_by` — maps each script's path (relative to `dir`) to a sort key so a caller can force
  #             load order; defaults to identity (lexical).
  # `assets`  — subdirectory of `dir` whose tree is mirrored into the mod via install_asset, or
  #             nil to skip. FNM_DOTMATCH is used so dotted dirs like `.metadata/` come along.
  def compile dir, without: [], sort_by: ->(path) { path }, assets: "assets"
    # Re-entrancy guard. The entry script that invokes compile (typically the mod's compile.rb)
    # lives in `dir` too, so unless it's the running program it gets `load`ed by the sweep below
    # and calls compile again. `$PROGRAM_NAME` covers the plain `ruby compile.rb` case; this
    # guard covers every other driver (a watcher, `ruby -e`, a test), turning that nested call
    # into a harmless no-op instead of infinite recursion.
    return [] if @compiling

    @compiling = true
    begin
      start = Time.now
      dir = Pathname.new(dir).expand_path
      reset_written_paths!

      skip = Set.new(without.map { |path| File.expand_path path, dir })
      skip << File.expand_path($PROGRAM_NAME)
      skip.merge $LOADED_FEATURES # bootstraps arrive via require; `load`ed generators never do

      Dir.glob(dir.join("**", "*.rb"))
        .map { |path| File.expand_path path }
        .reject { |path| skip.include? path }
        .sort_by { |path| sort_by.call Pathname.new(path).relative_path_from(dir).to_s }
        .each do |path|
          puts "Running #{Pathname.new(path).relative_path_from(dir)}"
          load path
        end

      if assets && File.directory?(assets_dir = dir.join(assets))
        Dir.glob(assets_dir.join("**", "*"), File::FNM_DOTMATCH).each do |src|
          next if File.directory? src

          install_asset src, Pathname.new(src).relative_path_from(assets_dir).to_s
        end
        puts "Copied static assets from #{assets}/"
      end

      cleanup_orphans.tap do |removed|
        puts "Removed #{removed.size} orphaned file(s)" unless removed.empty?
        puts "Compiled in #{(Time.now - start).round(3)}s"
      end
    ensure
      @compiling = false
    end
  end

  def delete path
    full_path = full_path_for path
    File.delete full_path if exists? full_path

    return unless full_path.to_s.start_with? root.to_s

    dir = full_path.dirname
    while dir.empty? and dir != root do
      File.rmdir dir
      dir = dir.dirname
    end
  end

  private

  # Write `data` to `full_path` only if the bytes differ from what's already on disk, then
  # record the path as a current output. Skipping unchanged files preserves the inode (and so
  # the game's inotify watch on it) and, crucially, keeps a full recompile from flooding the
  # watcher: only files that actually changed emit modify events, instead of every generated
  # file at once — which overwhelms the hot-reloader and can lock up or crash the game.
  def write_data full_path, data
    full_path = Pathname.new full_path
    mark_written full_path

    bytes = data.b
    return false if File.exist?(full_path) && File.binread(full_path) == bytes

    FileUtils.mkdir_p full_path.dirname
    File.write full_path, data
    true
  end

  # Remove directories under `base` that are now empty, deepest-first so a dir emptied only by
  # pruning its children is itself pruned.
  def prune_empty_dirs base
    Dir.glob(base.join("**", "*"), File::FNM_DOTMATCH)
      .reject { |path| %w[. ..].include? File.basename(path) } # FNM_DOTMATCH yields dir/. self-entries
      .select { |path| File.directory? path }
      .sort_by { |path| -path.length }
      .each { |dir| Dir.rmdir(dir) if Dir.empty?(dir) }
  end
end
