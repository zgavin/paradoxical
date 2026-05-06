require "os"

module Paradoxical::Games
  @registered = []

  class << self
    def register game_module
      @registered << game_module
    end

    def all
      @registered.dup
    end

    def find slug
      game = @registered.find do |m| m::SLUG == slug end
      return game unless game.nil?

      raise ArgumentError, "unknown game slug #{slug.inspect}; known: #{@registered.map { |m| m::SLUG }.inspect}"
    end

    # Resolves the runtime executable name for a game module:
    # - Windows users always get `<slug>.exe` (Windows binaries are .exe).
    # - Linux/macOS users get the bare slug if the game has a native
    #   port for the current OS, or `<slug>.exe` if it has to run via
    #   Proton/Wine (e.g. EU5 on Linux — Win-only game on a non-Win OS).
    def executable_for game_module
      base = game_module::SLUG
      if current_platform == :windows || !game_module::NATIVE_PLATFORMS.include?(current_platform) then
        "#{base}.exe"
      else
        base
      end
    end

    def current_platform
      return :windows if OS.windows?
      return :macos   if OS.mac?

      :linux
    end

    # Reads `rawVersion` from `launcher-settings.json`. Most PDS
    # titles ship this file at the install root; Imperator nests it
    # in a `launcher/` subdir; jomini-v2 layouts may put it one level
    # above the smoke's `game.root`. We search both bases (root and
    # parent) for both candidate paths.
    #
    # The `rawVersion` value may have a leading `v` (Stellaris,
    # CK3, EU4) or not (HOI4, Imperator); strip if present.
    def read_launcher_version game
      path = locate_in_install(game, "launcher-settings.json", "launcher/launcher-settings.json")
      return nil unless path

      raw = JSON.parse(File.read(path)).fetch("rawVersion", nil)
      return nil if raw.nil? || raw.empty?

      Gem::Version.new(raw.delete_prefix("v"))
    end

    # Reads a branch file (e.g. `caesar_branch.txt`) and pulls a
    # version out via the supplied regex.
    #
    # Note: branch files are unreliable as a sole version source —
    # both their format and their content are at Paradox's whim.
    # Example, EU5: 1.1.10 (real version) reports as `release/1.1.0`
    # (patch component lost), and a later patch changed the format
    # entirely to a build-id prefix scheme without any semver in it.
    # Prefer `read_build_checksum` + a per-game BUILD_VERSION_MAP
    # for any game where branch-file parsing has proven fragile.
    def read_branch_version game, filename, pattern
      path = locate_in_install(game, filename)
      return nil unless path

      File.read(path).match(pattern)&.then { |m| Gem::Version.new(m[1]) }
    end

    # Reads the 32-character build checksum from
    # `binaries/checksum.txt`. Build-time-stamped, also embedded
    # inline in the game's executable, changes per Paradox release —
    # so it's a reliable per-build discriminator.
    #
    # Pair with a per-game `BUILD_VERSION_MAP` to translate the hex
    # to a human-readable Gem::Version. Unknown builds (e.g. dev
    # branches, future releases not yet in the map) return nil; the
    # corrections module then applies all corrections unconditionally
    # since they're anchor-based and safely no-op on mismatch.
    def read_build_checksum game
      path = locate_in_install(game, "binaries/checksum.txt")
      return nil unless path

      File.read(path).strip.then { |s| s.empty? ? nil : s }
    end

    # Returns the first existing path for any of the given relative
    # paths, searched against both `game.root` and `game.root.parent`
    # (handles smoke-vs-Game-default-root differences for jomini-v2
    # `game/`-subdir layouts).
    def locate_in_install game, *relative_paths
      [game.root, game.root.parent].each do |base|
        relative_paths.each do |rel|
          candidate = base.join(rel)
          return candidate if File.exist?(candidate)
        end
      end
      nil
    end
  end
end
