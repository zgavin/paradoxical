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
      licenses.txt
      LICENSE.txt
      OFL.txt
      steam_appid.txt
      ThirdPartyLicenses.txt
      HOW_TO_MAKE_NEW_SHIPS.txt
      99_README_GRAMMAR.txt
      99_README_EDICTS.txt
      startup_info.txt
      TODO.txt
      robots.txt
      trigger_profile.txt
      fake.txt
      fake2.txt
      buildings_nudger_markers.txt
      unit_nudger_markers.txt
      particle_repository.txt
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
      /fonts/korean/
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

    # `FileParser#read` reads as UTF-8 by default and transparently
    # retries as Windows-1252 if the bytes are invalid UTF-8 — so the
    # smoke just calls `game.parse_file` once.
    # PARADOXICAL_PARSE_SMOKE_ENCODING is a diagnostic override —
    # pass `encoding:` explicitly to pin a specific encoding (and
    # disable the retry).
    forced_encoding = ENV["PARADOXICAL_PARSE_SMOKE_ENCODING"]

    allowlist_path = File.expand_path("../fixtures/parse_smoke_allow_#{slug}.yml", __dir__)
    allowlist = File.exist?(allowlist_path) ? Array(::YAML.safe_load_file(allowlist_path)) : []
    allowlist_set = allowlist.to_set

    # For jomini-v2 layouts the install root is one above `game.root`;
    # for jomini-v1 (HAS_GAME_SUBDIR=false) it is `game.root` itself.
    # Display/allowlist paths are computed relative to the install
    # root so engine-dir files (jomini/, clausewitz/) and game/ files
    # share a consistent prefix scheme.
    install_root = game_module::HAS_GAME_SUBDIR ? game.root.parent : game.root

    # Walk the game's own scripts under `game.root`, plus the
    # engine-default sibling dirs the engine ships (jomini/,
    # clausewitz/) so they get regression coverage too. Engine files
    # don't go through Game.parse_file (no corrections apply at the
    # engine level) — parsed via the bare Parser instead.
    script_roots = [game.root]
    if game_module::HAS_GAME_SUBDIR
      %w[jomini clausewitz].each do |engine|
        candidate = install_root.join(engine)
        script_roots << candidate if candidate.directory?
      end
    end

    files = script_roots.flat_map { |root| Dir.glob(File.join(root, "**/*")) }
      .uniq
      .select { |f| File.file?(f) && parseable_exts.include?(File.extname(f)) }
      .reject { |f| excluded_basenames.include?(File.basename(f)) }
      .reject { |f| excluded_path_substrings.any? { |s| f.include?(s) } }
      .reject { |f|
        # `excluded_root_dirs` is anchored to the start of each script
        # root's relative path, so it correctly excludes EU4's
        # console-transcript `tests/` without touching EU5's nested
        # `in_game/common/tests/`.
        owning_root = script_roots.find { |r| f.start_with?("#{r}/") }
        rel = f.sub("#{owning_root}/", "")
        excluded_root_dirs.any? { |d| rel.start_with?(d) }
      }
      .sort

    install_prefix = "#{install_root.to_s.chomp("/")}/"
    game_prefix    = "#{game.root.to_s.chomp("/")}/"

    it "parses every #{parseable_exts.join("/")} file under #{slug} (root: #{game.root})" do
      ok = 0
      failures = []
      allowlisted_pass = []
      allowlisted_fail = 0

      files.each do |full_path|
        # Display path is install-root-relative so engine and game/
        # files share a prefix scheme; allowlists are keyed off it.
        display = full_path.sub(/\A#{Regexp.escape(install_prefix)}/, "")
        on_allowlist = allowlist_set.include?(display)

        # Use Game.parse_file for both game/ and engine paths so BOM
        # stripping, per-game corrections, and the FileParser-level
        # Windows-1252 fallback flow through uniformly. Game files use
        # a relative path (so per-game corrections fire); engine files
        # use an absolute path (FileParser#full_path_for returns
        # absolute as-is) — corrections key off relative paths and
        # don't apply at the engine layer, which is fine since engine
        # files ship clean.
        arg = full_path.start_with?(game_prefix) ?
          full_path.sub(/\A#{Regexp.escape(game_prefix)}/, "") :
          full_path
        parsed = false
        last_error = nil
        begin
          game.parse_file(arg, encoding: forced_encoding)
          parsed = true
        rescue Paradoxical::Parser::ParseError, EncodingError, ArgumentError => e
          last_error = e
        end

        if parsed
          on_allowlist ? allowlisted_pass << display : ok += 1
        elsif on_allowlist
          allowlisted_fail += 1
        else
          label = last_error.is_a?(Paradoxical::Parser::ParseError) ? "" : "[#{last_error.class}] "
          first_line = last_error.message.lines.first&.chomp.to_s
          failures << { path: display, error: "#{label}#{first_line}" }
        end
      end

      total = files.size
      puts "\nParse smoke (#{slug}): #{total} files | #{ok} ok | " \
           "#{failures.size} failed | #{allowlisted_fail} allowlisted-fail | " \
           "#{allowlisted_pass.size} allowlisted-pass"

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
