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

  # A playset name that resolves to nothing is almost always a typo or a
  # stale config. Every launcher format should fail loudly rather than
  # silently enabling no mods (or, for JSON, dereferencing nil).
  describe "#enabled_mods playset validation" do
    let(:tmpdir) { Pathname.new(Dir.mktmpdir) }
    let(:user_dir) { Pathname.new(Dir.mktmpdir) }
    after do
      FileUtils.remove_entry(tmpdir) if Dir.exist?(tmpdir)
      FileUtils.remove_entry(user_dir) if Dir.exist?(user_dir)
    end

    def game_for(game_module, user_directory: tmpdir)
      Paradoxical::Game.new(game_module, root: tmpdir, user_directory: user_directory)
    end

    context "legacy launcher (no playset registry at all)" do
      it "raises for any playset name" do
        game = game_for(Paradoxical::Games::CK2)
        game.playset = "Anything"
        expect { game.enabled_mods }.to raise_error(/No playset named "Anything"/)
      end

      it "does not raise when no playset is set" do
        game = game_for(Paradoxical::Games::CK2)
        expect(game.enabled_mods).to eq([])
      end
    end

    context "sqlite launcher" do
      before do
        db = SQLite3::Database.new(user_dir.join("launcher-v2.sqlite").to_s)
        db.execute_batch(<<~SQL)
          CREATE TABLE mods (id TEXT, gameRegistryId TEXT);
          CREATE TABLE playsets (id TEXT, name TEXT);
          CREATE TABLE playsets_mods (playsetId TEXT, modId TEXT, enabled BOOLEAN, position INTEGER);
          INSERT INTO playsets (id, name) VALUES ('p1', 'Standard');
        SQL
        db.close
      end

      it "raises for an unknown playset name" do
        game = game_for(Paradoxical::Games::EU4, user_directory: user_dir)
        game.playset = "Nope"
        expect { game.enabled_mods }.to raise_error(/No playset named "Nope"/)
      end

      it "does not raise for a known playset name" do
        game = game_for(Paradoxical::Games::EU4, user_directory: user_dir)
        game.playset = "Standard"
        expect(game.enabled_mods).to eq([])
      end
    end

    context "json launcher" do
      before do
        File.write(
          user_dir.join("playsets.json"),
          JSON.generate("playsets" => [{ "name" => "Standard", "orderedListMods" => [] }]),
        )
      end

      it "raises for an unknown playset name" do
        game = game_for(Paradoxical::Games::EU5, user_directory: user_dir)
        game.playset = "Nope"
        expect { game.enabled_mods }.to raise_error(/No playset named "Nope"/)
      end

      it "does not raise for a known playset name" do
        game = game_for(Paradoxical::Games::EU5, user_directory: user_dir)
        game.playset = "Standard"
        expect(game.enabled_mods).to eq([])
      end
    end
  end
end
