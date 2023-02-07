module Paradoxical::Helper
  def glob s
    Paradoxical.game.glob s
  end

	def common_files dir
		glob "common/#{dir}/*.txt"
	end

	def update_mod_file ...
		Paradoxical.mod.update_file(...)
	end
	
	def write_mod_file ...
		Paradoxical.mod.write_file(...)
	end
  
  def build &block
    Paradoxical::Builder.new.build &block
  end
  
  def document whitespace: nil, path: nil, owner: nil, &block
    children = block.nil? ? [] : build( &block )
    
    Paradoxical::Elements::Document.new children, whitespace: whitespace, path: path, owner: ( owner or Paradoxical.mod )
  end
  
  def write document_or_path, &block
    document = document_or_path.is_a?( Paradoxical::Elements::Document ) ? document_or_path : Paradoxical::Elements::Document.new( owner: Paradoxical.mod, path: document_or_path )

    children = document.instance_variable_get :@children 

    children.concat build &block unless block.nil?
    
    Paradoxical.mod.write_file document.path, document.to_pdx
  end

	def parse_files ...
		Paradoxical.game.parse_files(...)
	end
  
  def parse ...
    Paradoxical.game.parse(...)
  end
end