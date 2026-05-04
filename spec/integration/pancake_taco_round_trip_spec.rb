RSpec.describe "PancakeTaco round-trip", :integration do
  game_slug = ENV["PARADOXICAL_EXAMPLE_GAME"] || "eu5"
  playset   = ENV["PARADOXICAL_EXAMPLE_PLAYSET"] || "Standard"
  mod_name  = ENV["PARADOXICAL_EXAMPLE_MOD"]

  if mod_name.nil? || mod_name.empty?
    it "is skipped (set PARADOXICAL_EXAMPLE_MOD to the mod's display name)" do
      skip "PARADOXICAL_EXAMPLE_MOD unset"
    end
  else
    require "paradoxical"

    # Drive the harness through the same `paradoxical!` entry point a
    # real mod script uses, so any regression in Game / Mod / launcher
    # construction surfaces here. (PancakeTaco's compile.rb invokes
    # this exact call shape.)
    paradoxical!(game: game_slug, playset: playset, mod: mod_name)

    if Paradoxical.game.mod.nil?
      it "is skipped (no mod named #{mod_name.inspect} in the #{playset.inspect} playset)" do
        skip "mod selection returned nil"
      end
    else
      mod_path = Paradoxical.game.mod.path
      parseable_exts = %w[.txt .gui .gfx].freeze

      files = Dir.glob(File.join(mod_path, "**/*"))
        .reject { |f| f.include?("/scripts/ruby/") }
        .select { |f| File.file?(f) && parseable_exts.include?(File.extname(f)) }
        .sort

      allowlist_path = File.expand_path("../fixtures/round_trip_allow.yml", __dir__)
      allowlist = File.exist?(allowlist_path) ? Array(::YAML.safe_load_file(allowlist_path)) : []

      mod_root_prefix = "#{mod_path.to_s.chomp('/')}/"

      files.each do |full_path|
        relative = full_path.sub(/\A#{Regexp.escape(mod_root_prefix)}/, "")

        if allowlist.include?(relative)
          it "round-trips #{relative} (allowlisted)" do
            skip "in spec/fixtures/round_trip_allow.yml"
          end
          next
        end

        it "round-trips #{relative}" do
          original_bytes = File.binread(full_path)
          # Parse via the active mod (the same path `parse_files` from
          # a mod script would take).
          document = Paradoxical.game.mod.parse_file(relative)

          data = document.bom? ? "\xEF\xBB\xBF".dup : String.new
          data << document.to_pdx
          data.encode!(document.encoding) unless document.encoding.nil?

          expect(data.b).to eq(original_bytes.b),
            "round-trip mismatch for #{relative}\n" \
            "original size: #{original_bytes.bytesize}, regenerated size: #{data.bytesize}"
        end
      end
    end
  end
end
