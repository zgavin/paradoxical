module Paradoxical::Helper
  # Game / playset / mod selection happens via the top-level
  # `paradoxical!` entry point now (defined in lib/paradoxical.rb).
  # Helper covers the read/write surface that mod scripts use after
  # setup is done.

  def game
    Paradoxical.game
  end

  delegate :delete, :parse_files, :parse, :mods, :glob, :mod, :mod_name, to: :game
  delegate :exists?, to: :mod

  def mod_enabled? name
    mod = mod_named(name)
    mod.present? and mod.enabled?
  end

  def common_files dir
    glob "common/#{dir}/*.txt"
  end

  def build &block
    Paradoxical::Builder.new.build &block
  end

  def document whitespace: nil, path: nil, owner: nil, &block
    children = block.nil? ? [] : build(&block)

    Paradoxical::Elements::Document.new children, whitespace: whitespace, path: path, owner: (owner or mod)
  end

  def write file_or_path, bom: true, &block
    file =
      if file_or_path.is_a? Paradoxical::Elements::Document then
        # Copy-on-write at the write boundary: if this document is the live parse-cache
        # entry, swap a pristine copy into the cache so the mutations below stay private
        # to this write and don't leak to anything that re-parses the same path.
        file_or_path.owner&.detach_from_cache file_or_path
        file_or_path.tap do |doc|
          children = doc.instance_variable_get :@children
          children.concat build &block unless block.nil?
        end
      elsif file_or_path.is_a? Paradoxical::Elements::Yaml then
        file_or_path.tap do |yaml|
          values = yaml.instance_variable_get :@values
          values.merge! build &block unless block.nil?
        end
      elsif %w{.txt .gfx .gui}.include? File.extname file_or_path then
        children = build &block
        Paradoxical::Elements::Document.new children, owner: mod, path: file_or_path, bom:
      elsif %w{.yml .yaml}.include? File.extname file_or_path then
        values = block.call
        Paradoxical::Elements::Yaml.new values, owner: mod, path: file_or_path
      else
        raise "unhandled file type for #{file_or_path}"
      end

    mod.write file
  end

  def run_directly?
    caller_locations.first.path == $PROGRAM_NAME
  end
end
