RSpec.describe "PancakeTaco round-trip", :integration do
  mod_root = ENV["PARADOXICAL_EXAMPLE_MOD"]

  if mod_root.nil? || mod_root.empty? || !File.directory?(mod_root)
    it "is skipped (set PARADOXICAL_EXAMPLE_MOD to enable)" do
      skip "PARADOXICAL_EXAMPLE_MOD unset or not a directory"
    end
  else
    require "paradoxical"

    parseable_exts = %w[.txt .gui .gfx].freeze

    files = Dir.glob(File.join(mod_root, "**/*"))
      .reject { |f| f.include?("/scripts/ruby/") }
      .select { |f| File.file?(f) && parseable_exts.include?(File.extname(f)) }
      .sort

    allowlist_path = File.expand_path("../fixtures/round_trip_allow.yml", __dir__)
    allowlist = File.exist?(allowlist_path) ? Array(::YAML.safe_load_file(allowlist_path)) : []

    wrapper_class = Class.new do
      include Paradoxical::FileParser
      attr_reader :root

      def initialize(root)
        @root = Pathname.new(root)
        @file_cache = {}
        @corrections = {}
      end
    end

    wrapper = wrapper_class.new(mod_root)

    files.each do |full_path|
      relative = full_path.sub(/\A#{Regexp.escape(mod_root.chomp("/"))}\/?/, "")

      if allowlist.include?(relative)
        it "round-trips #{relative} (allowlisted)" do
          skip "in spec/fixtures/round_trip_allow.yml"
        end
        next
      end

      it "round-trips #{relative}" do
        original_bytes = File.binread(full_path)
        document = wrapper.parse_file(relative)

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
