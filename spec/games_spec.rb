require "paradoxical"

RSpec.describe Paradoxical::Games do
  describe ".find" do
    it "resolves known slugs to their module" do
      expect(described_class.find("eu4")).to be(Paradoxical::Games::EU4)
      expect(described_class.find("eu5")).to be(Paradoxical::Games::EU5)
      expect(described_class.find("stellaris")).to be(Paradoxical::Games::Stellaris)
      expect(described_class.find("imperator")).to be(Paradoxical::Games::ImperatorRome)
      expect(described_class.find("ck2")).to be(Paradoxical::Games::CK2)
      expect(described_class.find("ck3")).to be(Paradoxical::Games::CK3)
      expect(described_class.find("v3")).to be(Paradoxical::Games::V3)
      expect(described_class.find("hoi4")).to be(Paradoxical::Games::HOI4)
    end

    it "raises on an unknown slug with the known list in the message" do
      expect { described_class.find("xcom") }
        .to raise_error(ArgumentError, /unknown game slug "xcom".*eu4.*eu5/m)
    end
  end

  describe ".all" do
    it "lists all 8 registered game modules" do
      expect(described_class.all.size).to eq(8)
      expect(described_class.all).to all(satisfy { |m| m.const_defined?(:SLUG) })
    end
  end

  describe "per-game module shape" do
    # Pin the shape so future games copy a consistent template and
    # `Game.new`/`paradoxical!` can rely on the constants being there.
    Paradoxical::Games.all.each do |game_module|
      describe game_module.name do
        %i[NAME SLUG STEAM_ID NATIVE_PLATFORMS HAS_GAME_SUBDIR LAUNCHER_FORMAT].each do |const|
          it "defines #{const}" do
            expect(game_module.const_defined?(const)).to be(true)
          end
        end

        it "lists only known platform symbols in NATIVE_PLATFORMS" do
          expect(game_module::NATIVE_PLATFORMS - %i[windows linux macos]).to be_empty
        end

        it "uses a known LAUNCHER_FORMAT (sqlite / json / legacy)" do
          expect(%i[sqlite json legacy]).to include(game_module::LAUNCHER_FORMAT)
        end

        it "defines a DSL submodule" do
          expect(game_module::DSL).to be_a(Module)
        end

        it "defines a CORRECTIONS hash" do
          expect(game_module::CORRECTIONS).to be_a(Hash)
        end

        it "responds to installed_version(game)" do
          expect(game_module).to respond_to(:installed_version)
        end
      end
    end
  end

  describe "version detection helpers" do
    # Use a fake game-like object exposing just `root` (a Pathname),
    # which is all the helpers consult.
    let(:tmpdir) { Dir.mktmpdir }
    after        { FileUtils.remove_entry(tmpdir) if Dir.exist?(tmpdir) }

    let(:fake_game) { Struct.new(:root).new(Pathname.new(tmpdir)) }

    describe ".read_branch_version" do
      it "parses a branch file at game.root via the supplied regex" do
        File.write(File.join(tmpdir, "eu4_branch.txt"), "release_1.37.5\n")
        v = described_class.read_branch_version(fake_game, "eu4_branch.txt", /release_(\S+)/)
        expect(v).to eq(Gem::Version.new("1.37.5"))
      end

      it "falls back to game.root.parent when the file isn't at root" do
        Dir.mkdir(File.join(tmpdir, "game"))
        File.write(File.join(tmpdir, "caesar_branch.txt"), "release/1.1.0\n")
        inner = Struct.new(:root).new(Pathname.new(File.join(tmpdir, "game")))
        v = described_class.read_branch_version(inner, "caesar_branch.txt", /release\/(\S+)/)
        expect(v).to eq(Gem::Version.new("1.1.0"))
      end

      it "returns nil when neither root nor parent has the file" do
        v = described_class.read_branch_version(fake_game, "nonexistent.txt", /release_(\S+)/)
        expect(v).to be_nil
      end

      it "returns nil when the regex doesn't match" do
        File.write(File.join(tmpdir, "eu4_branch.txt"), "garbage\n")
        v = described_class.read_branch_version(fake_game, "eu4_branch.txt", /release_(\S+)/)
        expect(v).to be_nil
      end
    end

    describe ".read_launcher_version" do
      it "parses rawVersion (Stellaris-style `vX.Y.Z`)" do
        File.write(File.join(tmpdir, "launcher-settings.json"), '{"rawVersion": "v4.3.5"}')
        v = described_class.read_launcher_version(fake_game)
        expect(v).to eq(Gem::Version.new("4.3.5"))
      end

      it "parses rawVersion (HOI4-style 4-component without leading v)" do
        File.write(File.join(tmpdir, "launcher-settings.json"), '{"rawVersion": "1.18.1.0"}')
        v = described_class.read_launcher_version(fake_game)
        expect(v).to eq(Gem::Version.new("1.18.1.0"))
      end

      it "returns nil when launcher-settings.json is missing" do
        expect(described_class.read_launcher_version(fake_game)).to be_nil
      end

      it "returns nil when rawVersion is absent" do
        File.write(File.join(tmpdir, "launcher-settings.json"), '{"gameId": "stellaris"}')
        expect(described_class.read_launcher_version(fake_game)).to be_nil
      end
    end
  end

  describe ".executable_for" do
    # Stubs OS so the test runs the same on any host. The OS gem is
    # what `current_platform` consults.
    def stub_platform(platform)
      allow(OS).to receive(:windows?).and_return(platform == :windows)
      allow(OS).to receive(:mac?).and_return(platform == :macos)
      allow(OS).to receive(:linux?).and_return(platform == :linux)
    end

    it "returns `<slug>.exe` on Windows for any game" do
      stub_platform(:windows)
      expect(described_class.executable_for(Paradoxical::Games::EU4)).to eq("eu4.exe")
      expect(described_class.executable_for(Paradoxical::Games::EU5)).to eq("eu5.exe")
    end

    it "returns the bare slug on Linux when the game has a native Linux port" do
      stub_platform(:linux)
      expect(described_class.executable_for(Paradoxical::Games::EU4)).to eq("eu4")
      expect(described_class.executable_for(Paradoxical::Games::Stellaris)).to eq("stellaris")
    end

    it "returns `<slug>.exe` on Linux for a Windows-only game (Proton/Wine)" do
      stub_platform(:linux)
      expect(described_class.executable_for(Paradoxical::Games::EU5)).to eq("eu5.exe")
    end

    it "returns the bare slug on macOS when the game has a native macOS port" do
      stub_platform(:macos)
      expect(described_class.executable_for(Paradoxical::Games::EU4)).to eq("eu4")
    end
  end
end
