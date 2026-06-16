require "paradoxical"
require "tmpdir"

# Regression coverage for `Paradoxical::Mod#initialize` — it dispatches
# on the active game's launcher format to read either a `.mod`
# descriptor (legacy SqliteConfig launcher) or a `.metadata/metadata.json`
# file (modern JsonConfig launcher). After Phase 5c removed
# `Game#jomini_version` in favor of `LAUNCHER_FORMAT`, both branches
# need to keep working.

RSpec.describe Paradoxical::Mod do
  let(:tmpdir) { Pathname.new(Dir.mktmpdir) }
  after        { FileUtils.remove_entry(tmpdir) if Dir.exist?(tmpdir) }

  # A minimal Game-like double exposing only what Mod.new touches:
  # `game_module` (for LAUNCHER_FORMAT) and `user_directory` (for
  # the `root` helper, indirectly).
  def fake_game(format)
    mod_struct = Module.new
    mod_struct.const_set(:LAUNCHER_FORMAT, format)
    Struct.new(:game_module, :user_directory).new(mod_struct, tmpdir)
  end

  # Builds a JSON-launcher mod rooted in tmpdir (the format EU5 and
  # other modern titles use), with a minimal metadata.json.
  def json_mod
    mod_root = tmpdir.join("foo_mod")
    FileUtils.mkdir_p(mod_root.join(".metadata"))
    File.write(
      mod_root.join(".metadata", "metadata.json"),
      JSON.dump(name: "Foo Mod", supported_game_version: "1.1.0", id: "12345"),
    )
    described_class.new(fake_game(:json), "12345", mod_root)
  end

  describe "#initialize" do
    context "with LAUNCHER_FORMAT = :sqlite" do
      it "parses the .mod descriptor at the given path" do
        descriptor = tmpdir.join("foo.mod")
        File.write(descriptor, %{name = "Foo Mod"\npath = "mod/foo"\nsupported_version = "1.37.5"\n})

        mod = described_class.new(fake_game(:sqlite), 42, descriptor)

        expect(mod.id).to eq(42)
        expect(mod.name).to eq("Foo Mod")
        expect(mod.supported_version).to eq("1.37.5")
      end
    end

    context "with LAUNCHER_FORMAT = :json" do
      it "reads name + supported version from .metadata/metadata.json" do
        mod_root = tmpdir.join("foo_mod")
        FileUtils.mkdir_p(mod_root.join(".metadata"))
        File.write(
          mod_root.join(".metadata", "metadata.json"),
          JSON.dump(name: "Foo Mod", supported_game_version: "1.1.0", id: "12345"),
        )

        mod = described_class.new(fake_game(:json), "12345", mod_root)

        expect(mod.id).to eq("12345")
        expect(mod.name).to eq("Foo Mod")
        expect(mod.supported_version).to eq("1.1.0")
        expect(mod.archive?).to be(false)
      end
    end

    context "with LAUNCHER_FORMAT = :legacy" do
      it "raises a clear error (CK2's launcher isn't supported)" do
        expect { described_class.new(fake_game(:legacy), 1, tmpdir) }
          .to raise_error(ArgumentError, /:legacy/)
      end
    end
  end

  describe "#write" do
    # Regression: #write re-encodes the serialized bytes via
    # `file.encoding`. Yaml localization elements had no `encoding`
    # accessor, so writing one raised NoMethodError before the fix.
    it "writes a Yaml localization file with a BOM and UTF-8 bytes" do
      mod = json_mod
      yaml = Paradoxical::Elements::Yaml.new(
        { GREETING: "hello" },
        path: "localization/english/test_l_english.yml",
        owner: mod,
      )

      expect { mod.write(yaml) }.not_to raise_error

      written = mod.root.join("localization/english/test_l_english.yml")
      # Yaml#bom? is always true, so the file leads with the UTF-8 BOM.
      expect(File.binread(written)).to start_with("\xEF\xBB\xBF".b)
      expect(File.read(written)).to include(%{l_english:\n GREETING: "hello"})
    end
  end
end
