require "paradoxical"
require "tmpdir"

# Regression coverage for `Game#parse_files`. The function used to
# spawn one Thread per file (problematic at scale — a mod loading
# thousands of files would create thousands of OS threads); this is
# now a bounded `Etc.nprocessors`-worker pool. Order preservation,
# pass-through of `mod:`/`encoding:` kwargs, and the
# zero/single/many-file branches all need to keep working.

RSpec.describe Paradoxical::Game do
  describe "#parse_files" do
    let(:tmpdir) { Pathname.new(Dir.mktmpdir) }
    after        { FileUtils.remove_entry(tmpdir) if Dir.exist?(tmpdir) }

    # CK2 uses the :legacy launcher format — no SQLite or JSON
    # mod-loading dependencies — so we can spin up a Game pointed at
    # any tmpdir without needing a real install.
    let(:game) do
      Paradoxical::Game.new(
        Paradoxical::Games::CK2,
        root: tmpdir,
        user_directory: "/tmp/no-paradoxical-mods-loaded",
      )
    end

    def write_file name, content
      File.write(tmpdir.join(name), content)
    end

    it "returns nil for an empty file list" do
      expect(game.parse_files).to be_nil
    end

    it "returns the single document directly when given one file" do
      write_file("a.txt", "value = A\n")

      result = game.parse_files("a.txt")

      expect(result).to be_a(Paradoxical::Elements::Document)
      expect(result["value"].value).to eq("A")
    end

    it "returns parsed documents in input order for multiple files" do
      # Use enough files to exceed the single-worker fast-path and
      # exercise the bounded pool. Order must survive the worker
      # threading (each worker writes into its assigned slot, not
      # appended).
      letters = ("a".."t").to_a # 20 files
      letters.each do |key|
        write_file("#{key}.txt", "value = #{key.upcase}\n")
      end

      result = game.parse_files(*letters.map { |k| "#{k}.txt" })

      expect(result.size).to eq(letters.size)
      letters.each_with_index do |key, i|
        actual = result[i]["value"].value
        expect(actual).to eq(key.upcase), "expected position #{i} to be '#{key.upcase}', got '#{actual}'"
      end
    end

    it "accepts a flat array argument" do
      write_file("a.txt", "value = A\n")
      write_file("b.txt", "value = B\n")

      result = game.parse_files(["a.txt", "b.txt"])

      expect(result.map { |d| d["value"].value }).to eq(%w[A B])
    end
  end
end
