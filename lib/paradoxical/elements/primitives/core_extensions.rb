class Object
  def to_pdx
    inspect
  end
end

class Symbol
  def to_pdx
    self.to_s
  end
  
  def quote
    self.to_s.quote
  end
  
  def literal
    self.to_s.literal
  end
end

class String
  prepend Paradoxical::Elements::Concerns::Impersonator::NativeComparisons
  
	IS_VALID_RAW_STRING_REGEXP = /^(hidden:event_target:|event_target:|trigger:|modifier:|value:|hidden:|parameter:|@|\w|-?\d+\.?\d*%+$)[\w\.]*$/ 	
  
  def to_pdx
    IS_VALID_RAW_STRING_REGEXP =~ self ? self : %{"#{self}"}
  end
  
  def quote
    Paradoxical::Elements::Primitives::String.new self, is_quoted: true
  end
  
  def literal
    Paradoxical::Elements::Primitives::String.new self, is_quoted: false
  end
end

class Float
  prepend Paradoxical::Elements::Concerns::Impersonator::NativeComparisons
  
  def to_pdx
    '%.3f' % self
  end
end

class Integer
  prepend Paradoxical::Elements::Concerns::Impersonator::NativeComparisons
  
  def to_pdx
    to_s
  end
end

class TrueClass
  def to_pdx
    "yes"
  end
end

class FalseClass
  def to_pdx
    "no"
  end
end

class Array
	def to_pdx
		Paradoxical::Elements::Document.new( self, whitespace: [''] ).to_pdx
	end
	
	def pdx_add_padding_lines
		self.map do |v| [ v, Paradoxical::Elements::Value.empty_line ] end.flatten(1)[0..-2]
	end
end