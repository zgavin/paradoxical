module Paradoxical::Helper
  def glob s
    Paradoxical.game.glob s
  end

	def common_files dir
		glob "common/#{dir}/*.txt"
	end
  
  def generate &block
    Paradoxical.generate &block
  end

	def update_mod_file *args, &block
		Paradoxical.mod.update_file *args, &block
	end
	
	def write_mod_file *args, &block
		Paradoxical.mod.write_file *args, &block
	end

	def parse_files *args
		Paradoxical.game.parse_files *args
	end
  
  def parse *args
    Paradoxical.game.parse *args
  end
end