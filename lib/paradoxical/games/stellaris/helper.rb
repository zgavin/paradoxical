module Paradoxical::Games::Stellaris::Helper
  # WARNING: the underlying save-file editor hasn't been exercised in
  # several years. It was written against an older Stellaris save
  # format and is almost certainly no longer functional against
  # modern releases — expect save-format drift (field names, section
  # shapes, the intel-manager malformedness shim) before any real
  # save round-trips. Kept for namespace shape; treat as a starting
  # point rather than a working tool.
  #
  # Drives the Editor lifecycle: instantiate, run the caller's edit
  # block, apply the post-edit fog-of-war cleanup (so the player
  # empire doesn't ship terra_incognita / hyperlane_systems /
  # visited_objects state that contradicts the edits), write back to
  # disk. Lives in Helper (extended onto `main` by `paradoxical!`)
  # rather than DSL (prepended onto Builder) because it takes a path
  # + block at the script's top level — not Builder-context.
  def edit path, game: nil, &block
    started_at = Time.now
    puts "Editing #{File.dirname path}"
    editor = Paradoxical::Games::Stellaris::Editor.new(path, game: game)
    done_parsing_at = Time.now
    puts "Parsing: #{"%.2f" % (done_parsing_at - started_at)}"
    editor.instance_exec(&block)
    editor.instance_exec do
      player = empires.first
      player.search("> &list&key-matches(/terra_incognita|hyperlane_systems|visited_objects/) &value").each(&:remove)
      empires[1..-1].flat_map do |e|
        e.search("> &list&key-matches(/terra_incognita|hyperlane_systems|visited_objects/) &value")
      end.each(&:remove)
    end
    done_editing_at = Time.now
    puts "Editing: #{"%.2f" % (done_editing_at - done_parsing_at)}"
    editor.write
    puts "Writing: #{"%.2f" % (Time.now - done_editing_at)}"
  rescue Exception => e
    puts e.inspect
    exit
  end
end
