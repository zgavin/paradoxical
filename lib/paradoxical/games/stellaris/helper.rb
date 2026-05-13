module Paradoxical::Games::Stellaris::Helper
  # `edit` is the top-level convenience for invoking the Stellaris
  # save-editor. It's distinct from the Builder-context DSL
  # (`add_resource`, `check_galaxy_setup_value`, …) in that it takes a
  # path and yields a block to mutate a save file — not script-tree
  # nodes — so it lives in Helper (extended onto `main` by
  # `paradoxical!`) rather than DSL (prepended onto Builder).
  def edit path, &block
    Paradoxical::Games::Stellaris::Editor.edit path, &block
  end
end
