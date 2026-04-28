require "paradoxical"

RSpec.describe Paradoxical::FileParser do
  let(:wrapper_class) do
    Class.new do
      include Paradoxical::FileParser
      attr_reader :root

      def initialize(root)
        @root = Pathname.new(root)
        @file_cache = {}
        @corrections = {}
      end
    end
  end

  let(:wrapper) { wrapper_class.new(Dir.pwd) }

  describe "#parse" do
    it "stamps @bom on the document when bom: true is passed" do
      doc = wrapper.parse("foo = 1\n", bom: true)
      expect(doc.bom?).to be(true)
    end

    it "stamps @bom = false by default" do
      doc = wrapper.parse("foo = 1\n")
      expect(doc.bom?).to be(false)
    end

    it "detects CRLF line endings from the input" do
      doc = wrapper.parse("foo = 1\r\nbar = 2\r\n")
      expect(doc.line_break).to eq("\r\n")
    end

    it "detects LF line endings from the input" do
      doc = wrapper.parse("foo = 1\nbar = 2\n")
      expect(doc.line_break).to eq("\n")
    end

    it "stamps the path and encoding on the document" do
      doc = wrapper.parse("foo = 1\n", path: "some/file.txt", encoding: "Windows-1252")
      expect(doc.path).to eq("some/file.txt")
      expect(doc.encoding).to eq("Windows-1252")
    end

    it "re-raises ParseError with the path prefixed onto the message" do
      expect {
        wrapper.parse("not = valid script *garbage*", path: "broken.txt")
      }.to raise_error(Paradoxical::Parser::ParseError, /broken\.txt:/)
    end

    it "re-raises ParseError without prefix when no path is given" do
      expect {
        wrapper.parse("not = valid script *garbage*")
      }.to raise_error(Paradoxical::Parser::ParseError)
    end
  end
end
