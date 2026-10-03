# Off-repo regression corpus of verified game builds
# (MODERNIZATION.md phase 1e). Needs PARADOXICAL_CORPUS set.
namespace :corpus do
  desc "Snapshot an installed game build into the corpus (root defaults to the game's default install root)"
  task :snapshot, [:slug, :root] do |_task, args|
    require "paradoxical"
    require_relative "../spec/support/corpus"

    game_module = Paradoxical::Games.find(args[:slug])
    game = Paradoxical::Game.new(game_module, root: args[:root], user_directory: "/tmp/no-paradoxical-mods-loaded")
    corpus = Paradoxical::Corpus.new(game_module)

    version = corpus.snapshot(game)
    puts "Snapshotted #{game_module::SLUG} #{version} into #{corpus.repo}"
  rescue Paradoxical::Corpus::Error => e
    abort e.message
  end

  # rake "corpus:fetch[eu5,branch=1.4-open-beta]"          current build of a branch
  # rake "corpus:fetch[eu5,3450311=2614…,3450312=2659…]"   pinned historical manifests
  # add expect=<version> to refuse a download detected as anything else
  desc "Download a build's text files from Steam with DepotDownloader and snapshot it"
  task :fetch, [:slug] do |_task, args|
    require "paradoxical"
    require_relative "../spec/support/corpus"

    manifests = {}
    branch = nil
    expect = nil

    args.extras.each do |extra|
      key, value = extra.split("=", 2)
      abort "expected depot=manifest, branch=name or expect=version, got #{extra.inspect}" if value.blank?

      if key == "branch" then
        branch = value
      elsif key == "expect" then
        expect = value
      else
        manifests[Integer(key)] = Integer(value)
      end
    end

    corpus = Paradoxical::Corpus.new(Paradoxical::Games.find(args[:slug]))
    version = corpus.fetch(manifests: manifests, branch: branch, expect: expect)
    puts "Fetched and snapshotted #{args[:slug]} #{version} into #{corpus.repo}"
  rescue Paradoxical::Corpus::Error, ArgumentError => e
    abort e.message
  end

  desc "Run the parse smoke against every stored build of a game (every game when slug is omitted)"
  task :smoke, [:slug] do |_task, args|
    require "paradoxical"
    require_relative "../spec/support/corpus"

    corpora =
      if args[:slug] then
        [Paradoxical::Corpus.new(Paradoxical::Games.find(args[:slug]))]
      else
        Paradoxical::Corpus.all
      end
    abort "The corpus is empty; store a build with corpus:snapshot first" if corpora.empty?

    failed = []

    corpora.each do |corpus|
      corpus.tags.each do |tag|
        result = corpus.smoke(tag)
        puts "#{result.passed? ? "ok  " : "FAIL"} #{result.summary}"
        failed << [corpus, result] unless result.passed?
      end
    end

    failed.each do |corpus, result|
      puts "\n===== #{corpus.game_module::SLUG} #{result.version} =====\n#{result.output}"
    end

    abort "\n#{failed.size} stored build(s) failed the parse smoke" unless failed.empty?
  rescue Paradoxical::Corpus::Error => e
    abort e.message
  end

  desc "Rebuild a game's corpus history in version order (every game when slug is omitted)"
  task :reorder, [:slug] do |_task, args|
    require "paradoxical"
    require_relative "../spec/support/corpus"

    corpora =
      if args[:slug] then
        [Paradoxical::Corpus.new(Paradoxical::Games.find(args[:slug]))]
      else
        Paradoxical::Corpus.all
      end

    corpora.each do |corpus|
      if corpus.ordered? then
        puts "#{corpus.game_module::SLUG}: already in version order"
      else
        corpus.reorder
        puts "#{corpus.game_module::SLUG}: reordered #{corpus.tags.size} builds"
      end
    end
  rescue Paradoxical::Corpus::Error => e
    abort e.message
  end

  desc "List the builds stored in the corpus for a game"
  task :list, [:slug] do |_task, args|
    require "paradoxical"
    require_relative "../spec/support/corpus"

    corpus = Paradoxical::Corpus.new(Paradoxical::Games.find(args[:slug]))
    puts corpus.tags
  rescue Paradoxical::Corpus::Error => e
    abort e.message
  end
end
