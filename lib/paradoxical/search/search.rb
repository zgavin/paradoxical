module Paradoxical::Search
  def self.parse data
    parse_result = Parser.new.parse data, reporter: Parslet::ErrorReporter::Deepest.new
  
  	Transformer.new.apply parse_result
  rescue Parslet::ParseFailed => error
	  puts error.parse_failure_cause.ascii_tree
		exit
  end
end