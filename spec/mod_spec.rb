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

    # A file whose bytes are unchanged is left untouched — same inode, so the game's inotify
    # watch on it survives, and a full recompile doesn't flood the watcher.
    it "leaves an unchanged file's inode intact on rewrite" do
      mod  = json_mod
      yaml = -> { Paradoxical::Elements::Yaml.new({ K: "v" }, path: "localization/english/x_l_english.yml", owner: mod) }

      mod.write(yaml.call)
      written = mod.root.join("localization/english/x_l_english.yml")
      ino = File.stat(written).ino

      mod.write(yaml.call)

      expect(File.stat(written).ino).to eq(ino)
    end

    it "rewrites a file whose content changed" do
      mod = json_mod

      mod.write(Paradoxical::Elements::Yaml.new({ K: "one" }, path: "localization/english/x_l_english.yml", owner: mod))
      mod.write(Paradoxical::Elements::Yaml.new({ K: "two" }, path: "localization/english/x_l_english.yml", owner: mod))

      expect(File.read(mod.root.join("localization/english/x_l_english.yml"))).to include(%{K: "two"})
    end

    it "records written paths as current outputs" do
      mod = json_mod
      mod.write(Paradoxical::Elements::Yaml.new({ K: "v" }, path: "localization/english/x_l_english.yml", owner: mod))

      expect(mod.written_paths).to include(File.expand_path(mod.root.join("localization/english/x_l_english.yml")).to_s)
    end
  end

  describe "#install_asset" do
    it "copies an asset and marks it as a current output" do
      mod = json_mod
      src = tmpdir.join("icon.dds")
      File.binwrite(src, "PNGDATA")

      expect(mod.install_asset(src, "gfx/icon.dds")).to be(true)

      dest = mod.root.join("gfx/icon.dds")
      expect(File.binread(dest)).to eq("PNGDATA")
      expect(mod.written_paths).to include(File.expand_path(dest).to_s)
    end

    it "skips the copy when the deployed file is already current (same size, not older)" do
      mod = json_mod
      src = tmpdir.join("icon.dds")
      File.binwrite(src, "PNGDATA")

      mod.install_asset(src, "gfx/icon.dds")
      dest = mod.root.join("gfx/icon.dds")
      ino = File.stat(dest).ino

      # dest was just written, so it's at least as new as src and the same size → skip.
      expect(mod.install_asset(src, "gfx/icon.dds")).to be(false)
      expect(File.stat(dest).ino).to eq(ino)
    end
  end

  describe "#cleanup_orphans" do
    it "deletes files not written this run, keeps written and marked ones, and prunes empty dirs" do
      mod = json_mod
      # The fixture's metadata.json is deployed via assets in a real compile; protect it here.
      mod.mark_written(".metadata/metadata.json")

      # A generated file (tracked via #write) and a stale leftover in the same tree.
      mod.write(Paradoxical::Elements::Yaml.new({ K: "v" }, path: "common/kept_l_english.yml", owner: mod))
      FileUtils.mkdir_p(mod.root.join("common/nested"))
      File.write(mod.root.join("common/nested/stale.txt"), "old")

      # A file deployed out-of-band but protected via #mark_written.
      File.write(mod.root.join("common/protected.txt"), "keep")
      mod.mark_written("common/protected.txt")

      removed = mod.cleanup_orphans

      expect(removed).to contain_exactly(mod.root.join("common/nested/stale.txt").to_s)
      expect(File.exist?(mod.root.join("common/kept_l_english.yml"))).to be(true)
      expect(File.exist?(mod.root.join("common/protected.txt"))).to be(true)
      # The now-empty nested dir is pruned.
      expect(File.exist?(mod.root.join("common/nested"))).to be(false)
    end

    it "reaps a file from a prior in-process build after reset_written_paths!" do
      mod = json_mod
      mod.mark_written(".metadata/metadata.json")

      # Build 1 emits a file, which is protected.
      mod.write(Paradoxical::Elements::Yaml.new({ K: "v" }, path: "common/gone_l_english.yml", owner: mod))
      expect(mod.cleanup_orphans).to be_empty

      # Build 2 (same Mod) no longer emits it — after reset it's stale and gets reaped.
      mod.reset_written_paths!
      mod.mark_written(".metadata/metadata.json")

      removed = mod.cleanup_orphans
      expect(removed).to contain_exactly(mod.root.join("common/gone_l_english.yml").to_s)
    end

    it "limits the sweep to the given subdirectories via `within`" do
      mod = json_mod
      File.write(mod.root.join(".metadata", "metadata.json"), File.read(mod.root.join(".metadata", "metadata.json")))
      FileUtils.mkdir_p(mod.root.join("gfx"))
      File.write(mod.root.join("gfx/orphan.txt"), "x")
      FileUtils.mkdir_p(mod.root.join("common"))
      File.write(mod.root.join("common/untouched.txt"), "y")

      mod.cleanup_orphans(within: "gfx")

      expect(File.exist?(mod.root.join("gfx/orphan.txt"))).to be(false)
      # Outside the `within` scope, so left alone even though it wasn't written.
      expect(File.exist?(mod.root.join("common/untouched.txt"))).to be(true)
    end
  end
  describe "#compile" do
    # Build a source dir of generator scripts. Each script records its load order in
    # $compile_order and emits a tracked file via $compile_mod (standing in for the global
    # `write` helper, which isn't wired up under the fake game these specs use).
    def build_src(mod)
      src = tmpdir.join("src")
      FileUtils.mkdir_p(src)
      %w[a b].each do |k|
        File.write(src.join("#{k}_gen.rb"), <<~RUBY)
          $compile_order << "#{k}"
          $compile_mod.write(Paradoxical::Elements::Yaml.new({ #{k.upcase}: "1" }, path: "common/#{k}_l_english.yml", owner: $compile_mod))
        RUBY
      end
      # A static asset (incl. the dotted .metadata dir) to mirror.
      FileUtils.mkdir_p(src.join("assets/gfx"))
      File.binwrite(src.join("assets/gfx/i.dds"), "DDS")
      FileUtils.mkdir_p(src.join("assets/.metadata"))
      File.write(src.join("assets/.metadata/metadata.json"), mod.root.join(".metadata/metadata.json").read)
      src
    end

    before { $compile_order = [] }

    it "loads scripts in order, mirrors assets, and reaps orphans" do
      mod = json_mod
      $compile_mod = mod
      src = build_src(mod)
      # A stale leftover from a prior build that no script emits.
      FileUtils.mkdir_p(mod.root.join("common"))
      File.write(mod.root.join("common/stale.txt"), "old")

      removed = mod.compile(src)

      expect($compile_order).to eq(%w[a b])
      expect(File.exist?(mod.root.join("common/a_l_english.yml"))).to be(true)
      expect(File.exist?(mod.root.join("common/b_l_english.yml"))).to be(true)
      expect(File.binread(mod.root.join("gfx/i.dds"))).to eq("DDS")
      expect(File.exist?(mod.root.join(".metadata/metadata.json"))).to be(true)
      expect(removed).to contain_exactly(mod.root.join("common/stale.txt").to_s)
    end

    it "honors a custom sort_by to force load order" do
      mod = json_mod
      $compile_mod = mod
      src = build_src(mod)

      # Force b ahead of a — the opposite of the default lexical order.
      order = { "b_gen.rb" => 0, "a_gen.rb" => 1 }
      mod.compile(src, sort_by: ->(path) { order.fetch(path, 99) })

      expect($compile_order).to eq(%w[b a])
    end

    it "skips scripts listed in `without`" do
      mod = json_mod
      $compile_mod = mod
      src = build_src(mod)

      mod.compile(src, without: ["a_gen.rb"])

      expect($compile_order).to eq(%w[b])
    end

    it "re-runs generators on every call (load, not require)" do
      mod = json_mod
      $compile_mod = mod
      src = build_src(mod)

      mod.compile(src)
      mod.compile(src)

      # Each generator ran on both compiles — a require-based sweep would skip the second.
      expect($compile_order).to eq(%w[a b a b])
    end

    it "no-ops a re-entrant compile instead of recursing" do
      mod = json_mod
      $compile_mod = mod
      src = build_src(mod)
      # A generator that re-invokes compile — stands in for the entry compile.rb being loaded
      # by the sweep under a driver other than `ruby compile.rb`.
      File.write(src.join("c_reenter.rb"), "$compile_mod.compile(#{src.to_s.inspect})")

      expect { mod.compile(src) }.not_to raise_error
      # The nested call bailed out, so each real generator still ran exactly once.
      expect($compile_order).to eq(%w[a b])
    end
  end
end
