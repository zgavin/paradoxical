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
      @registered.find { |m| m::SLUG == slug } or
        raise ArgumentError,
              "unknown game slug #{slug.inspect}; known: #{@registered.map { |m| m::SLUG }.inspect}"
    end

    # Resolves the runtime executable name for a game module:
    # - Windows users always get `<slug>.exe` (Windows binaries are .exe).
    # - Linux/macOS users get the bare slug if the game has a native
    #   port for the current OS, or `<slug>.exe` if it has to run via
    #   Proton/Wine (e.g. EU5 on Linux — Win-only game on a non-Win OS).
    def executable_for game_module
      base = game_module::SLUG
      if current_platform == :windows || !game_module::NATIVE_PLATFORMS.include?(current_platform)
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
    # version out via the supplied regex. Used by EU5 (no
    # launcher-settings.json available); other games go through
    # `read_launcher_version`.
    def read_branch_version game, filename, pattern
      path = locate_in_install(game, filename)
      return nil unless path

      File.read(path).match(pattern)&.then { |m| Gem::Version.new(m[1]) }
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
