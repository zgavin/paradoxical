require "fileutils"
require "find"
require "open3"
require "pathname"

# Local, off-repo snapshots of each verified game build's text files,
# so the parse smoke can be re-run against old builds without rolling
# Steam back (MODERNIZATION.md phase 1e). One git repo per game under
# `$PARADOXICAL_CORPUS/<slug>`, one tagged commit per build. Dev
# tooling only: lives under spec/ so it never ships in the gem.
class Paradoxical::Corpus
  class Error < StandardError; end

  # Everything Paradoxical can parse. Broader than the smoke's file
  # set on purpose: the smoke's exclusions stay in the smoke, so
  # changing them later re-applies to every stored build.
  EXTENSIONS = %w[.txt .gui .gfx .yml].freeze

  # Engine dirs that sit beside `game/` in jomini-v2 installs.
  ENGINE_DIRS = %w[jomini clausewitz].freeze

  # What `installed_version` reads, relative to the install root.
  # Snapshotting them means a checked-out build resolves the same
  # corrections it did as a real install.
  VERSION_FILES = %w[
    launcher-settings.json
    launcher/launcher-settings.json
    binaries/checksum.txt
  ].freeze

  # Repo bookkeeping that the mirror never deletes.
  KEEP = %w[.git .gitattributes].freeze

  def self.root
    dir = ENV["PARADOXICAL_CORPUS"]
    raise Error, "PARADOXICAL_CORPUS is unset; point it at the corpus directory" if dir.blank?

    path = Pathname.new(dir)
    raise Error, "#{path.parent} doesn't exist (is the drive mounted?)" unless path.parent.directory?

    path
  end

  # Every game with a repo in the corpus.
  def self.all corpus_root: root
    Paradoxical::Games.all.map do |game_module|
      new(game_module, corpus_root: corpus_root)
    end.select do |corpus| corpus.repo.join(".git").directory? end
  end

  # Outcome of smoking one stored build.
  SmokeResult = Struct.new(:version, :passed, :summary, :output, keyword_init: true) do
    alias_method :passed?, :passed
  end

  SMOKE_SPEC = File.expand_path("../integration/parse_smoke_spec.rb", __dir__)
  PROJECT_ROOT = File.expand_path("../..", __dir__)

  attr_reader :game_module, :repo, :worktree

  def initialize game_module, corpus_root: self.class.root
    @game_module = game_module
    @repo = Pathname.new(corpus_root).join(game_module::SLUG)
    # Outside the repo so the snapshot mirror never sees it; reused
    # across runs so moving between tags only rewrites changed files.
    @worktree = Pathname.new(corpus_root).join(".smoke", game_module::SLUG)
  end

  # Checks `tag` out into the smoke worktree. Returns the game root
  # to point the smoke at.
  def checkout tag
    raise Error, "#{game_module::SLUG} #{tag} isn't in the corpus" unless tag? tag

    if worktree.join(".git").exist? then
      git_in worktree, "checkout", "--quiet", "--detach", "--force", tag
    else
      worktree.dirname.mkpath
      git "worktree", "prune"
      git "worktree", "add", "--quiet", "--detach", worktree.to_s, tag
    end

    game_module::HAS_GAME_SUBDIR ? worktree.join("game") : worktree
  end

  # Runs the parse smoke against the stored build `tag` in a
  # subprocess, asserting the snapshot is detected as that version.
  def smoke tag
    env = {
      "PARADOXICAL_PARSE_SMOKE" => game_module::SLUG,
      "PARADOXICAL_PARSE_SMOKE_ROOT" => checkout(tag).to_s,
      "PARADOXICAL_PARSE_SMOKE_EXPECT_VERSION" => tag,
    }
    output, status = Open3.capture2e(env, "bundle", "exec", "rspec", SMOKE_SPEC, chdir: PROJECT_ROOT)

    SmokeResult.new(
      version: tag,
      passed: status.success?,
      summary: output[/^Parse smoke \(.*$/] || "no smoke summary (see output)",
      output: output,
    )
  end

  # Mirrors `game`'s install into the repo, commits, and tags the
  # commit with the detected version. Refuses unknown versions and
  # versions already in the corpus. Returns the version.
  def snapshot game
    version = game_module.installed_version(game)
    raise Error, "can't detect the installed #{game_module::SLUG} version under #{game.root}" if version.nil?

    init_repo
    raise Error, "#{game_module::SLUG} #{version} is already in the corpus" if tag? version.to_s

    install_root = game_module::HAS_GAME_SUBDIR ? game.root.parent : game.root
    mirror install_root, source_files(install_root)

    git "add", "--all"
    git "commit", "--quiet", "--allow-empty", "--no-verify", "-m", "#{game_module::SLUG} #{version}"
    git "tag", version.to_s

    version
  end

  def tags
    return [] unless repo.join(".git").directory?

    git_output("tag", "--list").lines.map(&:chomp).sort_by do |tag| Gem::Version.new(tag) end
  end

  def tag? name
    tags.include? name
  end

  private

  def source_files install_root
    script_roots =
      if game_module::HAS_GAME_SUBDIR then
        ["game", *ENGINE_DIRS].map do |dir| install_root.join(dir) end
      else
        [install_root]
      end

    scripts = script_roots.select(&:directory?).flat_map do |dir|
      Find.find(dir.to_s).select do |path|
        EXTENSIONS.include?(File.extname(path)) and File.file?(path)
      end
    end

    versions = VERSION_FILES.map do |rel| install_root.join(rel).to_s end.select do |path| File.file? path end

    (scripts + versions).uniq.map do |path| Pathname.new(path).relative_path_from(install_root) end
  end

  def mirror install_root, relative_paths
    wanted = relative_paths.map(&:to_s).to_set

    existing_files.each do |rel|
      repo.join(rel).delete unless wanted.include? rel
    end
    prune_empty_dirs

    relative_paths.each do |rel|
      target = repo.join(rel)
      target.dirname.mkpath
      FileUtils.cp install_root.join(rel), target
    end
  end

  def existing_files
    files = []

    Find.find(repo.to_s) do |path|
      rel = Pathname.new(path).relative_path_from(repo).to_s
      if KEEP.include? rel then
        Find.prune
      elsif File.file? path then
        files << rel
      end
    end

    files
  end

  def prune_empty_dirs
    Dir.glob(repo.join("**/").to_s).sort_by(&:length).reverse_each do |dir|
      next if Pathname.new(dir) == repo or dir.include?("/.git/")

      Dir.rmdir dir if Dir.empty? dir
    end
  end

  def init_repo
    return if repo.join(".git").directory?

    repo.mkpath
    git "init", "--quiet", "--initial-branch=main"
    # Shipped bytes are the point: no line-ending conversion, ever.
    git "config", "core.autocrlf", "false"
    repo.join(".gitattributes").write("* -text\n")
  end

  # Signing is off so snapshots never block on a key prompt; this repo
  # is never pushed anywhere.
  def git *args
    git_in repo, *args
  end

  def git_in dir, *args
    ok = system "git", "-C", dir.to_s, "-c", "commit.gpgsign=false", "-c", "tag.gpgsign=false", *args
    raise Error, "git #{args.join(" ")} failed in #{dir}" unless ok
  end

  def git_output *args
    output = IO.popen(["git", "-C", repo.to_s, *args], &:read)
    raise Error, "git #{args.join(" ")} failed in #{repo}" unless $?.success?

    output
  end
end
