RSpec.describe "parse smoke", :parse_smoke do
  slug = ENV["PARADOXICAL_PARSE_SMOKE"]

  if slug.nil? || slug.empty?
    it "is skipped (set PARADOXICAL_PARSE_SMOKE to a game slug)" do
      skip "PARADOXICAL_PARSE_SMOKE unset (e.g. eu5, stellaris, eu4 — see Paradoxical::Games)"
    end
  else
    require "paradoxical"

    parseable_exts = %w[.txt .gui .gfx].freeze

    # Some files share an extension with script files but aren't script
    # format. The same basenames recur across every PDX game. Filter by
    # basename, not by path, and don't conflate with the allowlist
    # (which is for script files we expect to fail to parse, a
    # different category).
    excluded_basenames = %w[
      checksum_manifest.txt
      caesar_branch.txt
      caesar_rev.txt
      clausewitz_branch.txt
      clausewitz_rev.txt
      eu4_branch.txt
      eu4_rev.txt
      console_history.txt
      credits.txt
      credits_l_simp_chinese.txt
      license-fi.txt
      LICENSE.txt
      OFL.txt
      steam_appid.txt
      ThirdPartyLicenses.txt
      HOW_TO_MAKE_NEW_SHIPS.txt
      99_README_GRAMMAR.txt
      99_README_EDICTS.txt
      startup_info.txt
      TODO.txt
      trigger_profile.txt
    ].to_set

    # Whole directories of non-script content. Path substrings since
    # the same dirs recur across games. /licenses/ vs /licences/ —
    # Imperator uses British spelling.
    excluded_path_substrings = %w[
      /sound/banks/
      /licenses/
      /licences/
      /patchnotes/
      /previewer_assets/
      /pdx_launcher/
    ].freeze

    # Directories at the root of the game install that aren't script.
    # Anchored (vs. excluded_path_substrings) because some games nest
    # legitimately-named directories deeper — e.g. EU5 ships real test
    # scripts at in_game/common/tests/ while EU4's root tests/ is
    # console-command transcripts.
    excluded_root_dirs = %w[
      tests/
    ].freeze

    game_module = Paradoxical::Games.find(slug)

    # Game.new resolves install/user paths from the module's defaults
    # (NAME, HAS_GAME_SUBDIR), wires the launcher dispatch, and
    # auto-registers per-version corrections — which is exactly the
    # state the smoke wants. PARADOXICAL_PARSE_SMOKE_ROOT overrides
    # the install root for off-default Steam library locations.
    game = Paradoxical::Game.new(
      game_module,
      root: ENV["PARADOXICAL_PARSE_SMOKE_ROOT"],
      user_directory: "/tmp/no-paradoxical-mods-loaded",
    )

    # Encoding fallbacks live on the game module (EU4 has a
    # Windows-1252 fallback for its older non-UTF-8 files; the rest
    # ship pure UTF-8).
    encodings = if (override = ENV["PARADOXICAL_PARSE_SMOKE_ENCODING"])
      [override]
    else
      [nil] + game_module::ENCODING_FALLBACKS
    end

    allowlist_path = File.expand_path("../fixtures/parse_smoke_allow_#{slug}.yml", __dir__)
    allowlist = File.exist?(allowlist_path) ? Array(::YAML.safe_load_file(allowlist_path)) : []
    allowlist_set = allowlist.to_set

    root_prefix_for_filter = "#{game.root.to_s.chomp('/')}/"
    files = Dir.glob(File.join(game.root, "**/*"))
      .select { |f| File.file?(f) && parseable_exts.include?(File.extname(f)) }
      .reject { |f| excluded_basenames.include?(File.basename(f)) }
      .reject { |f| excluded_path_substrings.any? { |s| f.include?(s) } }
      .reject { |f| excluded_root_dirs.any? { |d| f.sub(root_prefix_for_filter, "").start_with?(d) } }
      .sort

    it "parses every #{parseable_exts.join('/')} file under #{slug} (root: #{game.root})" do
      ok = 0
      failures = []
      allowlisted_pass = []
      allowlisted_fail = 0

      files.each do |full_path|
        relative = full_path.sub(/\A#{Regexp.escape(root_prefix_for_filter)}/, "")
        on_allowlist = allowlist_set.include?(relative)

        parsed = false
        last_error = nil
        encodings.each do |enc|
          begin
            game.parse_file(relative, encoding: enc)
            parsed = true
            break
          rescue Paradoxical::Parser::ParseError, EncodingError, ArgumentError => e
            last_error = e
          end
        end

        if parsed
          on_allowlist ? allowlisted_pass << relative : ok += 1
        elsif on_allowlist
          allowlisted_fail += 1
        else
          label = last_error.is_a?(Paradoxical::Parser::ParseError) ? "" : "[#{last_error.class}] "
          first_line = last_error.message.lines.first&.chomp.to_s
          failures << { path: relative, error: "#{label}#{first_line}" }
        end
      end

      total = files.size
      puts "\nParse smoke (#{slug}): #{total} files | #{ok} ok | #{failures.size} failed | #{allowlisted_fail} allowlisted-fail | #{allowlisted_pass.size} allowlisted-pass"

      unless allowlisted_pass.empty?
        puts "  Files in allowlist that now parse — consider removing:"
        allowlisted_pass.first(20).each { |p| puts "    + #{p}" }
        puts "    ... and #{allowlisted_pass.size - 20} more" if allowlisted_pass.size > 20
      end

      # Optional dump of all failures for analysis. Set
      # PARADOXICAL_PARSE_SMOKE_DUMP to a file path to write a
      # YAML-shaped list of every failing path.
      if (dump = ENV["PARADOXICAL_PARSE_SMOKE_DUMP"]) && !failures.empty?
        File.open(dump, "w") do |f|
          failures.each { |fail| f.puts "- #{fail[:path]}" }
        end
        puts "  Wrote #{failures.size} failing paths to #{dump}"
      end

      if failures.empty?
        expect(failures).to be_empty
      else
        report = failures.first(50).map { |f| "  - #{f[:path]}\n      #{f[:error]}" }.join("\n")
        report += "\n  ... and #{failures.size - 50} more" if failures.size > 50

        raise "#{failures.size} unexpected parse failures (allowlist at #{allowlist_path}):\n#{report}"
      end
    end
  end
end
