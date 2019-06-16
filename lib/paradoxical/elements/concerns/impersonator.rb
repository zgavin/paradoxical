module Paradoxical::Elements::Concerns::Impersonator  
  # The purpose behind this module is to allow for the original value created
  # by paradox (or a modder) to be retained and output again if unchanged.
  # Since script files enforce no consistent formatting of values, there are  
  # many ways to express the same thing.  If we converted all valuesto native  
  # ruby types some information would be lost and diffs would be inconsistent.

  extend ActiveSupport::Concern
  
  included do
    extend ClassMethods
  end
  
  module NativeComparisons
    %i{ < > <=> <= >= == === equal? != eql?}.each do |method|
      define_method method do |other|
        other = other.to_real if other.is_a? Paradoxical::Elements::Concerns::Impersonator
      
        super( other)
      end
    end
  end

  module ClassMethods
    def impersonate impersonated_class, conversion_method=nil
      @impersonated_class = impersonated_class
      @conversion_method = ( conversion_method or ( 'to_' + impersonated_class.name[0].downcase ) ).to_sym
    end
    
    def conversion_method
      @conversion_method
    end
    
    def impersonated_class
      @impersonated_class
    end

    def impersonate_methods *methods, &block
      methods.each do |method|
        define_method method do |*args|
          block.call method, *args
        end
      end      
    end
  
    def impersonate_infix_methods methods
      methods.each do |method|
        define_method method do |other|
          other = other.to_real if other.is_a? Paradoxical::Elements::Concerns::Impersonator

          to_real.send(method, other) 
        end
      end
    end
  end
  
  def initialize value
		@value = value
  end

  def dup
		self.class.new @value.dup
  end

  def to_pdx				
		@value
  end
	
  %i{to_s to_i to_f}.each do |m|
    define_method m do
      @value.send(m)
    end
  end
  
  def hash
    @value.hash
  end
  
  def to_real
    @value.send( self.class.conversion_method )
  end
  
  def is_a? klass
    impersonated_class = self.class.impersonated_class
    
    klass == impersonated_class or impersonated_class.ancestors.include? klass or super
  end
  
  %i{ < > <=> <= >= == === equal? != eql?}.each do |method|
    define_method method do |other|
      other = other.to_real if other.is_a? Paradoxical::Elements::Concerns::Impersonator
      
      to_real.send(method, other)
    end
  end
  
  def inspect
    %{#{@value.inspect}@pdx}
  end
  
	def respond_to? sym, include_private=false
		super or @value.respond_to?( sym, include_private )
	end
	
	def method_missing sym, *args, &block
		super unless @value.respond_to?( sym )
    
    self.class.send :define_method, sym do |*args, &block|
      @value.send sym, *args, &block
    end
		
    self.send( sym, *args, &block )
	end
end