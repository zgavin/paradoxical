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
      credits.txt
      license-fi.txt
      OFL.txt
    ].to_set

    # Whole directories of non-script content. Path substrings since the
    # same dirs recur across games.
    excluded_path_substrings = %w[
      /sound/banks/
    ].freeze

    game_label = ENV["PARADOXICAL_PARSE_SMOKE_GAME"] ||
      File.basename(game_root.chomp("/").sub(/\/game\z/, "")).downcase.gsub(/\s+/, "_")

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

        begin
          wrapper.parse_file(relative)
          on_allowlist ? allowlisted_pass << relative : ok += 1
        rescue Paradoxical::Parser::ParseError, Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError, ArgumentError => e
          if on_allowlist
            allowlisted_fail += 1
          else
            label = e.is_a?(Paradoxical::Parser::ParseError) ? "" : "[#{e.class}] "
            first_line = e.message.lines.first&.chomp.to_s
            failures << { path: relative, error: "#{label}#{first_line}" }
          end
        end
      end

      total = files.size
      puts "\nParse smoke (#{game_label}): #{total} files | #{ok} ok | #{failures.size} failed | #{allowlisted_fail} allowlisted-fail | #{allowlisted_pass.size} allowlisted-pass"

      unless allowlisted_pass.empty?
        puts "  Files in allowlist that now parse — consider removing:"
        allowlisted_pass.first(20).each { |p| puts "    + #{p}" }
        puts "    ... and #{allowlisted_pass.size - 20} more" if allowlisted_pass.size > 20
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
