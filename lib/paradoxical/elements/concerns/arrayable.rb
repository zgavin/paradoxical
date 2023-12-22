module Paradoxical::Elements::Concerns::Arrayable  
  extend ActiveSupport::Concern

  NOT_IMPLEMENTED_METHODS = %i{ 
    & * + - <=> == assoc bsearch bsearch_index combination compact compact! eql? flatten!
    hash initialize_copy inspect join max min pack permutation product rassoc repeated_combination
    repeated_permutation sum to_h to_s transpose uniq uniq! zip |
  }

  DELEGATED_METHODS = %i{ 
    all? any? at count drop empty? fetch first frozen? last length none? reverse rotate sample shuffle size
    slice sort take to_a values_at
  }

  DELEGATED_ENUMERATOR_METHODS = %i{ 
    collect cycle each each_index drop_while find_index index map reject reverse_each rindex select
    take_while
  }

  DELEGATED_MUTATING_METHODS = %i{ 
    reverse! rotate! shuffle! sort! sort_by!
  }

  CUSTOM_METHODS = %i{ 
    << [] []= append clear collect! concat delete delete_at delete_if dig fill insert keep_if map!
    pop prepend push reject! replace select! shift slice! unshift
  }
    
  included do
    delegate *DELEGATED_METHODS, to: :children, allow_nil: true 
  end

  DELEGATED_ENUMERATOR_METHODS.each do |m|
    define_method m do |*args, &block|
      return self.to_enum m if args.empty? and block.nil?
  
      result = @children.send m, *args, &block
  
      if result.equal? @children then
        return self
      else
        result
      end
    end
  end

  DELEGATED_MUTATING_METHODS.each do |m|
    define_method m do |*args, &block|
      @children.send(m, *args, &block)
    
      self
    end
  end    

  # Custom methods that delegate to children

  def << object
    raise ArgumentError.new "Must be Paradoxical::Elements::Node" unless object.is_a? Paradoxical::Elements::Node
  
    @children << object
  
    object.send( :parent=, self )
  
    self
  end
  
  def [] *args
    if [::String, Symbol, Paradoxical::Elements::Primitives::String].any? do |klass| args.first.is_a?(klass) end  then
      key = args.first.to_s.downcase
      
      @children.find do |obj| obj.respond_to?(:key) and obj.key.to_s.downcase == key end
    else
      @children[*args]
    end
  end

  def []= *args, value
    if args.first.is_a? String or args.first.is_a? Symbol then
      key = args.first.to_s
      
      property = self[key]
      
      if property.nil? then
				child = @children.reverse_each.find do |child| child.is_a? Paradoxical::Elements::Property end
				property = Paradoxical::Elements::Property.new( key, '=', value ) 
				if child.present? then
					child.insert_after property
				else	
        	self << property
				end
        
        value
      elsif property.is_a? Paradoxical::Elements::Property then
        property.value = value
      else
        raise ArgumentError.new "A string key must resolve to a Paradoxical::Elements::Node"
      end
    else    
      Array(value).each do |object| 
        raise ArgumentError.new "Must be Paradoxical::Elements::Node" unless object.is_a? Paradoxical::Elements::Node
    
        object.send( :parent=, self ) 
      end
    
      @children[*args] = value 
    end
  end

  def clear
    @children.each do |object| object.send( :parent=, nil ) end
  
    @children.clear
  
    self
  end

  def concat *args
    args.each do |objects| 
      objects.each do |object| 
        raise ArgumentError.new "Must be Paradoxical::Elements::Node" unless object.is_a? Paradoxical::Elements::Node
      
        object.send( :parent=, self ) 
      end
    end
  
    @children.concat *args
  
    self
  end

  def delete object, &block
    @children.delete( object, &block ).tap do |result|
      object.send( :parent=, nil ) if result.equal? object
    end
  end

  def delete_at index 
    @children.delete_at( index ).tap do |result|
      result.send( :parent=, nil ) unless result.nil?
    end
  end

  def delete_if &block
    return self.to_enum :delete_if if block.nil?
  
    @children.delete_if do |object| 
      block.call( object ).tap do |result|
        object.send( :parent=, nil ) if result
      end
    end
  
    self
  end

  def dig *indexes
    result = at indexes.shift
  
    ( indexes.empty? or result.nil? ) ? result : result.dig( *indexes )
  end

  def fill *args, &block
    if block.nil? then
      object, *rest = *args
    
      raise ArgumentError.new "Must be Paradoxical::Elements::Node" unless object.is_a? Paradoxical::Elements::Node
      
      @children.fill *rest do
        result = object.dup 
      
        result.send( :parent=, self ) 
      
        result
      end
    else
      @children.fill *args do |i|
        object = block.call i
      
        raise ArgumentError.new "Must be Paradoxical::Elements::Node" unless object.is_a? Paradoxical::Elements::Node
      
        result = object.dup 
      
        result.send( :parent=, self ) 
      
        result
      end
    end
    
    self
  end
  
  def descendents
    @children.map do |object| object.respond_to?(:descendents) ? [object, object.descendents] : object end.flatten
  end

  def insert index, *objects
    objects.each do |object| 
      raise ArgumentError.new "Must be Paradoxical::Elements::Node" unless object.is_a? Paradoxical::Elements::Node
    
      object.send( :parent=, self ) 
    end
  
    @children.insert index, *objects
  
    self
  end

  def keep_if &block
    return self.to_enum :keep_if if block.nil?
  
    @children.keep_if do |object| 
      block.call( object ).tap do |result|
        object.send( :parent=, nil ) unless result
      end
    end
  
    self
  end

  def map! &block
    return self.to_enum :map! if block.nil?
  
    @children.map! do |original_object| 
      new_object = block.call( original_object )
    
      new_object.send( :parent=, self ) and original_object.send( :parent=, nil ) unless new_object == original_object
    
      new_object
    end
  
    self
  end

  alias_method :collect!, :map!

  def pop n=1
    @children.pop(n)&.tap do |result|
      Array(result).each do |object| 
        object.send( :parent=, nil ) 
      end
    end
  end

  def push *objects
    objects.each do |object| 
      raise ArgumentError.new "Must be Paradoxical::Elements::Node" unless object.is_a? Paradoxical::Elements::Node
    
      object.send( :parent=, self ) 
    end
  
    @children.push *objects
  
    self
  end

  alias_method :append, :push

  def reject!
    return self.to_enum :reject! if block.nil?
  
    @children.reject! do |object| 
      block.call( object ).tap do |result|
        object.send( :parent=, nil ) if result
      end
    end
  
    self
  end

  def replace new_children
    @children.each do |object|
      object.send( :parent=, nil ) 
    end
  
    @children.replace new_children
    
    @children.each do |object|
      object.send( :parent=, self ) 
    end    
  
    self
  end

  def select!  &block
    return self.to_enum :select! if block.nil?
  
    @children.select! do |object| 
      block.call( object ).tap do |result|
        object.send( :parent=, nil ) unless result
      end
    end
  
    self
  end

  def shift n=1
    @children.shift(n)&.tap do |result|  
      Array(result).each do |object| 
        object.send( :parent=, nil ) 
      end
    end
  end

  def slice! *args
    @children.slice!(*args).tap do |objects|
      objects.each do |object| 
        object.send( :parent=, nil ) 
      end
    end
  end

  def unshift *objects
    objects.each do |object| 
      raise ArgumentError.new "Must be Paradoxical::Elements::Node" unless object.is_a? Paradoxical::Elements::Node
    
      object.send( :parent=, self ) 
    end
  
    @children.unshift *objects
  
    self
  end

  alias_method :prepend, :unshift

  # Accessors

  def all
    @children.dup
  end

  def lists
    @children.select do |obj| obj.is_a? Paradoxical::Elements::List end
  end
  
  def values 
    @children.select do |obj| obj.is_a? Paradoxical::Elements::Value end
  end

  def properties
    @children.select do |obj| obj.is_a? Paradoxical::Elements::Property end
  end
	
	def comments
		@children.select do |obj| obj.is_a? Paradoxical::Elements::Comment end
	end

  def keyable
    @children.select do |obj| obj.respond_to? :key end
  end 
	
	def keys
		keyable.map(&:key)
	end
  
  def value_for key
    key = key.to_s.downcase
    
    @children.find do |obj| obj.is_a? Paradoxical::Elements::Property and obj.key.downcase == key end&.value
  end

  private

  attr_reader :children
end