require 'os'

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
  end
end
