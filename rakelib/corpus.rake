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
