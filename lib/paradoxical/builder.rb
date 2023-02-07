class Paradoxical::Builder
  attr_reader :elements
  
  def build parent=nil, &block
    @parent = parent
    
    @elements = []
    
    self.instance_exec &block
    
    @elements.reject! do |element| element.parent.present? end 
      
    @elements.pop while elements.last.try :empty_line?
    
    @elements
  end
  
  def ignore! *elements    
    elements.each do |element|
      index = @elements.index do |other| other.equal? element end
        
      next if index.nil?
    
      @elements.delete_at index
    end
    
    elements.length == 1 ? elements.first : elements
  end 
  
  def push element
    @elements.push element
    
    element
  end
  
  def push! element    
    return element.map do |e| push! e end if element.is_a? Array
      
    raise ArgumentError.new "expected a Node or Array as argument" unless element.is_a? Paradoxical::Elements::Node
    
    @parent.ignore! element unless @parent.nil?
    
    element.remove unless element.parent.nil?
    
    push element
    
    element
  end
  
  def pop!
    @elements.pop    
  end
  
	def list key, *args, **opts, &block    
    args = args.flatten.map do |arg|
      arg.is_a?(Paradoxical::Elements::Node) ? arg : val(arg)
    end
    
    args.concat( self.class.new.build self, &block ) unless block.nil?
    
	  push Paradoxical::Elements::List.new key, args, **opts 
	end
  alias_method :l, :list

	def property key, operator, value=nil, whitespace: nil
	  push Paradoxical::Elements::Property.new key, operator, value, whitespace: whitespace
	end
  alias_method :p, :property
  
  def val value, whitespace: nil
    push Paradoxical::Elements::Value.new value, whitespace: whitespace
  end
  alias_method :v, :val
  
  def comment comment, whitespace: nil, inline: nil
		whitespace ||= [" "] if inline
    push Paradoxical::Elements::Comment.new " #{comment}", whitespace: whitespace
  end
  alias_method :c, :comment
  
  def string string, **opts
    Paradoxical::Elements::Primitives::String.new string, **opts
  end

	def empty_list k
		list k, []
	end

	def empty_line  
    push Paradoxical::Elements::Value.empty_line
	end

	def pdx_not *args, &block
		obj = l 'NOT', *args, &block
	  
		obj.single_line! if obj.singleton?
	
		obj
	end
	alias_method :not_, :pdx_not
	
	def pdx_else *args, &block
		obj = l 'else', *args, &block
		
		obj.whitespace = [ ' ', ' ', ' ', nil ]
		
		obj
	end
	alias_method :else_, :pdx_else
	
	def pdx_else_if *args, &block
		obj = l 'else_if', *args, &block
		
		obj.whitespace = [ ' ', ' ', ' ', nil ]
		
		obj
	end
	alias_method :else_if_, :pdx_else_if
  
  def pdx_if_else_if iterable, &block    
    iterable.each_with_index.map do |value, i|
      if iterable.first == value then
        pdx_if do 
          instance_exec value, i, &block 
        end
      else
        pdx_else_if do
          instance_exec value, i, &block
        end
      end
    end
  end
	alias_method :if_else_if_, :pdx_if_else_if
  
  def event_target key, *args, &block
    l "event_target:#{key}", *args, &block
  end
  
  def position x, y
    l( 'position', p('x', '=', x), p('y', '=', y) ).single_line!
  end
	
	def off_screen
		position( -10_000, -10_000 )
	end
  
  SIZE_KEYS = {
    container: %w{width height}
  }
  
  def size x, y, parent: nil
    parent = parent.key == 'containerWindowType' ? :container : nil if parent.respond_to?(:key)
    
    x_key, y_key = parent.nil? ? %w{x y} : SIZE_KEYS[parent]
    
    l( 'size', p( x_key, '=', x ), p( y_key, '=', y ) ).single_line!
  end

	%w{ if while AND NAND OR NOR }.each do |word|
		define_method "pdx_#{word.downcase}" do |*args, &block|
			l word, *args, &block
		end
		
		define_method "#{word.downcase}_" do |*args, &block|
			l word, *args, &block
		end
	end

	%w{ set check change subtract multiply divide modulo }.each do |word|
		key = "#{word}_variable"
	
		define_method key do |which, operator, value=nil|			
			if value.nil? then
				value = operator
				operator = '='
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
    if value.is_a? String then
      l( 'add_resource', p( resource, 1 ), p( mult, value ) )
    else
      l( 'add_resource', p( resource, value ) ).single_line!
    end
  end
  
  def remove_resource( resource, value )
    if value.is_a? String then
      l( 'add_resource', p( resource, -1 ), p( mult, value ) )
    else
      l( 'add_resource', p( resource, -1 * value ) ).single_line!
    end
  end
  
  def country_event *args, **opts, &block
    if args.count == 1 and [::String, String].any? do |klass| args.first.is_a? klass end then
      l( 'country_event', p("id", args.first) ).single_line!
    else
      l 'country_event', *args, **opts, &block
    end
  end
  
  def limit *args, &block
		obj = l 'limit', *args, &block
	  
		obj.single_line! if obj.singleton?
	
		obj
  end

	def pdx_obj key, *args, **opts, &block
		args = args.map do |v| v.nil? ? empty_line : v end
	
    if args.empty? and block.nil? then
			string key
	  elsif args.all? do |obj| obj.is_a? Paradoxical::Elements::Node end then
	    l key, *args, **opts, &block
    elsif args.none? do |obj| obj.is_a? Paradoxical::Elements::Node end then          
			p key, *args, **opts
    else
      raise ArgumentError.new "expected all Node or all Primitive arguments"
	  end
	end
	
	def _
		empty_line
	end

	def method_missing sym, *args, **opts, &block    
	  super if sym.to_s.ends_with? '='
	
		return empty_line if sym == :_

	  pdx_obj sym.to_s, *args, **opts, &block
	end
end