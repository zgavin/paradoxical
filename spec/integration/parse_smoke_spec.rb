RSpec.describe "parse smoke", :parse_smoke do
  game_root = ENV["PARADOXICAL_PARSE_SMOKE"]

  if game_root.nil? || game_root.empty? || !File.directory?(game_root)
    it "is skipped (set PARADOXICAL_PARSE_SMOKE to a game root)" do
      skip "PARADOXICAL_PARSE_SMOKE unset or not a directory"
    end
  else
    require "paradoxical"

    parseable_exts = %w[.txt .gui .gfx].freeze

    # Some files share an extension with script files but aren't script
    # format. The same basenames recur across every PDX game. Filter by
    # basename, not by path, and don't conflate with the allowlist (which
    # is for script files we expect to fail to parse, a different
    # category).
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
      license-fi.txt
      OFL.txt
      steam_appid.txt
      ThirdPartyLicenses.txt
    ].to_set

    # Whole directories of non-script content. Path substrings since the
    # same dirs recur across games. /licenses/ vs /licences/ — Imperator
    # uses British spelling.
    excluded_path_substrings = %w[
      /sound/banks/
      /licenses/
      /licences/
      /patchnotes/
      /previewer_assets/
      /pdx_launcher/
    ].freeze

    game_label = ENV["PARADOXICAL_PARSE_SMOKE_GAME"] ||
      File.basename(game_root.chomp("/").sub(/\/game\z/, "")).downcase.gsub(/\s+/, "_")

    # Encodings to try, in order. Most games ship pure UTF-8 so the list
    # is just [nil] (no hint, read raw). EU4 (jomini v1, 2013) is mostly
    # Windows-1252 but a handful of files with non-Latin characters
    # (Korean province names, the Tengri events, the Mamluk missions)
    # are actually UTF-8 — so we try UTF-8 first and fall back. The
    # parse_file cache populates only on success, so the retry path is
    # cheap.
    # PARADOXICAL_PARSE_SMOKE_ENCODING overrides to a single forced
    # encoding (useful for diagnostic runs).
    encoding_fallbacks_per_game = {
      "europa_universalis_iv" => ["Windows-1252"],
    }.freeze
    encodings = if (override = ENV["PARADOXICAL_PARSE_SMOKE_ENCODING"])
      [override]
    else
      [nil] + (encoding_fallbacks_per_game[game_label] || [])
    end

    allowlist_path = File.expand_path("../fixtures/parse_smoke_allow_#{game_label}.yml", __dir__)
    allowlist = File.exist?(allowlist_path) ? Array(::YAML.safe_load_file(allowlist_path)) : []
    allowlist_set = allowlist.to_set

    files = Dir.glob(File.join(game_root, "**/*"))
      .select { |f| File.file?(f) && parseable_exts.include?(File.extname(f)) }
      .reject { |f| excluded_basenames.include?(File.basename(f)) }
      .reject { |f| excluded_path_substrings.any? { |s| f.include?(s) } }
      .sort

    wrapper_class = Class.new do
      include Paradoxical::FileParser
      attr_reader :root

      def initialize(root)
        @root = Pathname.new(root)
        @file_cache = {}
        @corrections = {}
      end
    end

    wrapper = wrapper_class.new(game_root)

    it "parses every #{parseable_exts.join('/')} file under #{game_root.inspect} (game: #{game_label})" do
      ok = 0
      failures = []
      allowlisted_pass = []
      allowlisted_fail = 0

      root_prefix = "#{game_root.chomp('/')}/"

      files.each do |full_path|
        relative = full_path.sub(/\A#{Regexp.escape(root_prefix)}/, "")
        on_allowlist = allowlist_set.include?(relative)

        parsed = false
        last_error = nil
        encodings.each do |enc|
          begin
            wrapper.parse_file(relative, encoding: enc)
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
      puts "\nParse smoke (#{game_label}): #{total} files | #{ok} ok | #{failures.size} failed | #{allowlisted_fail} allowlisted-fail | #{allowlisted_pass.size} allowlisted-pass"

      unless allowlisted_pass.empty?
        puts "  Files in allowlist that now parse — consider removing:"
        allowlisted_pass.first(20).each { |p| puts "    + #{p}" }
        puts "    ... and #{allowlisted_pass.size - 20} more" if allowlisted_pass.size > 20
      end

      # Optional dump of all failures for analysis. Set
      # PARADOXICAL_PARSE_SMOKE_DUMP to a file path to write a YAML-shaped
      # list of every failing path (suitable for piping into an allowlist).
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
