class Paradoxical::Generator
	def l k, *args
		opts = args.extract_options!
	
	  Paradoxical::Elements::List.new k, args, opts
	end

	def p key,operator,value=nil
	  Paradoxical::Elements::Property.new key,operator,value
	end

	def empty_list k
		Paradoxical::Elements::List.new k, []
	end

	def empty_line
		Paradoxical::Elements::Value.new Paradoxical::Elements::Primitives::String.new '', is_quoted: false
	end
  
  def comment s
    Paradoxical::Elements::Comment.new " #{s}\r\n"
  end

	def pdx_not *args
		obj = l 'NOT', *args
	  
		obj.single_line! if obj.singleton?
	
		obj
	end
	
	def pdx_else *args
		obj = l 'else', *args
		
		obj.whitespace = [ ' ', ' ', ' ', nil ]
		
		obj
	end
	
	def pdx_else_if *args
		obj = l 'else_if', *args
		
		obj.whitespace = [ ' ', ' ', ' ', nil ]
		
		obj
	end
  
  def pdx_if_else_if *args    
    [ 
      pdx_if( *args.first ),
      *args[1..-1].map do |arg| pdx_else_if *arg end
    ]
  end
  
  def pdx_if_else_if_else *args
    [ 
      pdx_if( *args.first ),
      *args[1..-2].map do |arg| pdx_else_if *arg end,
      pdx_else( *args.last )        
    ]
  end
  
  def position x, y
    l( 'position', p('x', '=', x), p('y', '=', y) ).single_line!
  end
  
  SIZE_KEYS = {
    standard: %w{x y},
    full: %w{width height}
  }
  
  def size x, y, keys: :standard
    x_key, y_key = SIZE_KEYS[keys]
    
    l( 'size', p(x_key, '=', x), p(y_key, '=', y) ).single_line!
  end

	%w{ if while AND NAND OR NOR }.each do |word|
		define_method "pdx_#{word.downcase}" do |*args|
			l word, *args
		end
	end

	%w{ set check change subtract multiply divide }.each do |word|
		key = "#{word}_variable"
	
		define_method key do |which, operator, value=nil|			
			if value.nil? then
				value = operator
				operator = '='
			end
		
			if not value.is_a? Paradoxical::Elements::Primitives::String and value.is_a? String and not ( value.start_with? '@' or %w{ owner space_owner root this prev prevprev from fromfrom }.include? value ) then
				value = value.quote
			end
		
			l( key, p('which', which), p('value', operator, value ) ).single_line!
		end
	end
	
  def resource_stockpile_compare resource, operator, value=nil
		if value.nil? then
			value = operator
			operator = '='
		end
	
		l( 'resource_stockpile_compare', p('resource', resource ), p('value', operator, value ) ).single_line!
  end
  
  def add_resource( resource, value )
    l( 'add_resource', p( resource, value ) ).single_line!
  end
  
  def limit *args
		obj = l 'limit', *args
	  
		obj.single_line! if obj.singleton?
	
		obj
  end

	def pdx_obj key, *args  
		args = args.map do |v| v.nil? ? Paradoxical::Elements::Value.new('') : v end
	
		if args.empty? then
			Paradoxical::Elements::Primitives::String.new key
	  elsif (1..2).include? args.count and args.none? do |obj| obj.is_a? Paradoxical::Elements::List or obj.is_a? Paradoxical::Elements::Property end then
	    p key, *args
	  else
			l key, *args
	  end
	end

	def method_missing sym, *args, &block    
	  super if sym.to_s.ends_with? '='
	
		return empty_line if sym == :_

	  pdx_obj(sym.to_s, *args)
	end
end