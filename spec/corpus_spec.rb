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

    it "stores every file as 0644 whatever its mode at the source" do
      install.join("game/in_game/common/foo.txt").chmod(0o755)
      corpus.snapshot(game)

      tree = IO.popen(["git", "-C", repo.to_s, "ls-tree", "-r", "1.3.11"], &:read)
      expect(tree.lines.map do |line| line.split.first end.uniq).to eq(["100644"])
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

  describe "#checkout" do
    before do
      install_build "54cd"
      write "game/in_game/gui/old.gui", "old = {}\n"
      corpus.snapshot(game)

      install_build "d9c8"
      install.join("game/in_game/gui/old.gui").delete
      write "game/in_game/gui/new.gui", "new = {}\n"
      corpus.snapshot(game)
    end

    it "checks a stored build out into the smoke worktree and returns its game root" do
      root = corpus.checkout("1.3.11")

      expect(root).to eq(corpus_root.join(".smoke/eu5/game"))
      expect(root.join("in_game/gui/old.gui")).to exist
      expect(root.join("in_game/gui/new.gui")).not_to exist
    end

    it "moves the same worktree between builds" do
      corpus.checkout("1.3.11")
      root = corpus.checkout("1.4.0")

      expect(root.join("in_game/gui/new.gui")).to exist
      expect(root.join("in_game/gui/old.gui")).not_to exist
    end

    it "leaves the snapshot work tree on the latest build" do
      corpus.checkout("1.3.11")

      expect(repo.join("game/in_game/gui/new.gui")).to exist
    end

    it "refuses a build that isn't stored" do
      expect { corpus.checkout("9.9.9") }.to raise_error(described_class::Error, /isn't in the corpus/)
    end
  end

  # End to end: runs the real parse smoke in a subprocess against a
  # tiny fake EU5 corpus.
  describe "#smoke" do
    before do
      install_build "54cd"
      write "game/in_game/common/ok.txt", "foo = { bar = 1 }\n"
      corpus.snapshot(game)

      install_build "d9c8"
      write "game/in_game/common/broken.txt", "foo = { bar = 1\n"
      corpus.snapshot(game)
    end

    it "passes a build that parses and is detected as its tag" do
      result = corpus.smoke("1.3.11")

      expect(result).to be_passed, result.output
      expect(result.summary).to match(/Parse smoke \(eu5 1\.3\.11\): \d+ files/)
    end

    it "fails a build with a file that doesn't parse" do
      result = corpus.smoke("1.4.0")

      expect(result).not_to be_passed
      expect(result.output).to include("broken.txt")
    end

    it "fails a build whose tag doesn't match the detected version" do
      system "git", "-C", repo.to_s, "tag", "1.3.9", "1.3.11", exception: true

      result = corpus.smoke("1.3.9")

      expect(result).not_to be_passed
      expect(result.output).to include("detects eu5 1.3.9")
    end
  end

  describe "#fetch" do
    # Stands in for DepotDownloader: logs its arguments, copies the
    # fake install into `-dir`, and records each pinned manifest the
    # way the real tool does (unless told to skip one).
    let(:fake_depotdownloader) do
      @dir.join("DepotDownloader").tap do |path|
        path.write(<<~RUBY)
          #!/usr/bin/env ruby
          require "fileutils"
          File.open(ENV.fetch("FAKE_DD_LOG"), "a") do |f| f.puts ARGV.join(" ") end
          exit 1 if ENV["FAKE_DD_FAIL"]

          dir = ARGV[ARGV.index("-dir") + 1]
          FileUtils.cp_r(File.join(ENV.fetch("FAKE_DD_SOURCE"), "."), dir)
          FileUtils.mkdir_p(File.join(dir, ".DepotDownloader/staging"))
          File.write(File.join(dir, ".DepotDownloader/staging/chunk.txt"), "in flight")

          if (i = ARGV.index("-depot")) then
            depot = ARGV[i + 1]
            manifest = ARGV[ARGV.index("-manifest") + 1]
            unless ENV["FAKE_DD_SKIP_DEPOT"] == depot then
              File.write(File.join(dir, ".DepotDownloader/\#{depot}_\#{manifest}.manifest"), "")
            end
          end
        RUBY
        path.chmod(0o755)
      end
    end

    let(:log) { @dir.join("depotdownloader.log") }

    around do |example|
      keys = %w[FAKE_DD_LOG FAKE_DD_SOURCE FAKE_DD_FAIL FAKE_DD_SKIP_DEPOT]
      original = ENV.to_h.slice(*keys)
      ENV["FAKE_DD_LOG"] = log.to_s
      ENV["FAKE_DD_SOURCE"] = install.to_s
      example.run
    ensure
      keys.each do |key| ENV[key] = original[key] end
    end

    before do
      install_build "54cd"
      write "game/in_game/common/foo.txt", "foo = 1\n"
    end

    def fetch **options
      corpus.fetch(depotdownloader: fake_depotdownloader.to_s, username: "someone", **options)
    end

    it "fetches a branch's current build for the game's platform and snapshots it" do
      expect(fetch(branch: "1.3-open-beta")).to eq(Gem::Version.new("1.3.11"))

      command = log.read.lines.map(&:chomp)
      expect(command.size).to eq(1)
      expect(command.first).to include(
        "-app 3450310 -os windows", "-branch 1.3-open-beta", "-username someone -remember-password",
      )
      expect(committed_files("1.3.11")).to contain_exactly(
        ".gitattributes", "binaries/checksum.txt", "game/in_game/common/foo.txt",
      )
    end

    it "fetches pinned manifests one depot at a time" do
      fetch(manifests: { 3450311 => 111, 3450312 => 222 })

      expect(log.read.lines.map(&:chomp)).to contain_exactly(
        a_string_including("-app 3450310 -depot 3450311 -manifest 111"),
        a_string_including("-app 3450310 -depot 3450312 -manifest 222"),
      )
      expect(corpus.tags).to eq(["1.3.11"])
    end

    it "removes the staging dir after snapshotting" do
      fetch

      expect(corpus_root.join(".staging/eu5")).not_to exist
    end

    it "refuses to snapshot when a pinned depot wasn't downloaded" do
      ENV["FAKE_DD_SKIP_DEPOT"] = "3450312"

      expect { fetch(manifests: { 3450311 => 111, 3450312 => 222 }) }
        .to raise_error(described_class::Error, /depot 3450312 manifest 222 wasn't downloaded/)
      expect(corpus.tags).to be_empty
      expect(corpus_root.join(".staging/eu5/game/in_game/common/foo.txt")).to exist
    end

    it "snapshots a download detected as the expected version" do
      expect(fetch(expect: "1.3.11")).to eq(Gem::Version.new("1.3.11"))
    end

    it "refuses a download detected as a different version than expected" do
      expect { fetch(expect: "1.3.10") }
        .to raise_error(described_class::Error, /expected eu5 1.3.10 but detected 1.3.11; staging kept/)
      expect(corpus.tags).to be_empty
      expect(corpus_root.join(".staging/eu5/binaries/checksum.txt")).to exist
    end

    it "stops when DepotDownloader fails" do
      ENV["FAKE_DD_FAIL"] = "1"

      expect { fetch }.to raise_error(described_class::Error, /DepotDownloader failed/)
      expect(corpus.tags).to be_empty
    end
  end

  describe "#filelist_patterns" do
    let(:patterns) do
      corpus.filelist_patterns.map do |pattern| Regexp.new(pattern.delete_prefix("regex:")) end
    end

    def selected? path
      patterns.any? do |pattern| pattern.match? path end
    end

    it "selects text files and version files with either separator" do
      expect(selected?("game/in_game/common/foo.txt")).to be(true)
      expect(selected?("game\\localization\\english\\foo_l_english.yml")).to be(true)
      expect(selected?("binaries\\checksum.txt")).to be(true)
      expect(selected?("launcher/launcher-settings.json")).to be(true)
      expect(selected?("launcher\\launcher-settings.json")).to be(true)
    end

    it "skips everything else" do
      expect(selected?("game/gfx/texture.dds")).to be(false)
      expect(selected?("binaries/eu5.exe")).to be(false)
      expect(selected?("game/settings.json")).to be(false)
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
