module Paradoxical::Games
  # Resolves a versioned CORRECTIONS hash down to the set of
  # corrections that apply to a given installed version of a game.
  #
  # CORRECTIONS shape:
  #
  #   {
  #     "1.0.0" => {
  #       "path/to/file.gui"       => ->(data) { ... },
  #       "path/to/another.txt"    => ->(data) { ... },
  #     },
  #     "1.2.0" => {
  #       "path/to/file.gui"       => nil,                # Paradox fixed it; no longer apply
  #       "path/to/new_problem.txt" => ->(data) { ... },  # new correction at this version
  #     },
  #   }
  #
  # Walk versions in ascending order, only those <= installed. For
  # each path, the latest non-nil entry wins; an explicit `nil`
  # removes a previously-defined correction.
  #
  # If `installed` is nil (e.g. the game's version file is missing or
  # we don't yet know how to parse it for this game), apply every
  # correction unconditionally — corrections are conservative byte
  # mutations and a no-op when the target pattern isn't present.
  module Corrections
    def self.resolve corrections, installed
      return {} if corrections.empty?

      ordered = corrections.keys.sort_by { |v| Gem::Version.new(v) }
      ordered = ordered.select { |v| Gem::Version.new(v) <= installed } if installed

      ordered.each_with_object({}) do |version, applicable|
        corrections[version].each do |path, block|
          if block.nil?
            applicable.delete(path)
          else
            applicable[path] = block
          end
        end
      end
    end
  end
end
