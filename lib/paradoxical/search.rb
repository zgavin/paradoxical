module Paradoxical::Search
  def self.parse data
    Parser.parse data
  rescue Parser::ParseError => error
    puts data
	  puts error.message
		exit
  end
end