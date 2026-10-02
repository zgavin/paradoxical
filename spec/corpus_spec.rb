require "paradoxical"
require "tmpdir"
require_relative "support/corpus"

RSpec.describe Paradoxical::Corpus do
  # CI's git has no identity configured.
  git_identity = {
    "GIT_AUTHOR_NAME" => "corpus spec", "GIT_AUTHOR_EMAIL" => "corpus@example.invalid",
    "GIT_COMMITTER_NAME" => "corpus spec", "GIT_COMMITTER_EMAIL" => "corpus@example.invalid",
  }

  around do |example|
    original = ENV.to_h.slice(*git_identity.keys)
    ENV.update(git_identity)
    Dir.mktmpdir do |dir|
      @dir = Pathname.new(dir)
      example.run
    end
  ensure
    git_identity.each_key do |key| ENV[key] = original[key] end
  end

  let(:install) { @dir.join("install") }
  let(:corpus_root) { @dir.join("corpus") }
  let(:corpus) { described_class.new(Paradoxical::Games::EU5, corpus_root: corpus_root) }
  let(:repo) { corpus_root.join("eu5") }

  def write path, data
    install.join(path).dirname.mkpath
    install.join(path).binwrite(data)
  end

  # Suffix `d9c8` maps to EU5 1.4.0, `54cd` to 1.3.11.
  def install_build checksum_suffix
    write "binaries/checksum.txt", "#{"0" * 28}#{checksum_suffix}\n"
  end

  def game
    Paradoxical::Game.new(Paradoxical::Games::EU5, root: install.join("game"), user_directory: @dir.join("user"))
  end

  def committed_files tag
    IO.popen(["git", "-C", repo.to_s, "ls-tree", "-r", "--name-only", tag], &:read).lines.map(&:chomp)
  end

  describe "#snapshot" do
    before do
      install_build "54cd"
      write "game/in_game/common/foo.txt", "\xEF\xBB\xBFfoo = 1\r\n"
      write "game/in_game/gui/bar.gui", "bar = {}\n"
      write "game/localization/english/baz_l_english.yml", "l_english:\n"
      write "game/in_game/gfx/texture.dds", "binary"
      write "clausewitz/gui/engine.gui", "engine = {}\n"
      write "binaries/eu5.exe", "binary"
    end

    it "commits the text files and version files under a version tag" do
      expect(corpus.snapshot(game)).to eq(Gem::Version.new("1.3.11"))

      expect(corpus.tags).to eq(["1.3.11"])
      expect(committed_files("1.3.11")).to contain_exactly(
        ".gitattributes",
        "binaries/checksum.txt",
        "clausewitz/gui/engine.gui",
        "game/in_game/common/foo.txt",
        "game/in_game/gui/bar.gui",
        "game/localization/english/baz_l_english.yml",
      )
    end

    it "stores shipped bytes exactly, BOM and CRLF included" do
      corpus.snapshot(game)

      blob = IO.popen(["git", "-C", repo.to_s, "cat-file", "blob", "1.3.11:game/in_game/common/foo.txt"], &:read)
      expect(blob.b).to eq("\xEF\xBB\xBFfoo = 1\r\n".b)
    end

    it "mirrors a later build, dropping files it no longer ships" do
      corpus.snapshot(game)

      install_build "d9c8"
      install.join("game/in_game/gui/bar.gui").delete
      write "game/in_game/gui/new.gui", "new = {}\n"
      corpus.snapshot(game)

      expect(corpus.tags).to eq(["1.3.11", "1.4.0"])
      expect(committed_files("1.4.0")).to include("game/in_game/gui/new.gui")
      expect(committed_files("1.4.0")).not_to include("game/in_game/gui/bar.gui")
      expect(committed_files("1.3.11")).to include("game/in_game/gui/bar.gui")
      expect(repo.join("game/in_game/gui/bar.gui")).not_to exist
    end

    it "refuses a version that's already in the corpus" do
      corpus.snapshot(game)

      expect { corpus.snapshot(game) }.to raise_error(described_class::Error, /already in the corpus/)
      expect(corpus.tags).to eq(["1.3.11"])
    end

    it "refuses a build it can't identify" do
      install_build "ffff"

      expect { corpus.snapshot(game) }.to raise_error(described_class::Error, /can't detect/)
      expect(repo).not_to exist
    end
  end

  describe ".root" do
    around do |example|
      original = ENV["PARADOXICAL_CORPUS"]
      example.run
    ensure
      ENV["PARADOXICAL_CORPUS"] = original
    end

    it "requires PARADOXICAL_CORPUS" do
      ENV["PARADOXICAL_CORPUS"] = nil
      expect { described_class.root }.to raise_error(described_class::Error, /unset/)
    end

    it "refuses a location whose parent is missing, e.g. an unmounted drive" do
      ENV["PARADOXICAL_CORPUS"] = @dir.join("unmounted/corpus").to_s
      expect { described_class.root }.to raise_error(described_class::Error, /mounted/)
    end

    it "returns the configured location" do
      ENV["PARADOXICAL_CORPUS"] = corpus_root.to_s
      expect(described_class.root).to eq(corpus_root)
    end
  end
end
