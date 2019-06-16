class Paradoxical::Elements::Primitives::Color
  def initialize value
		@value = value
  end

  def dup
		self.class.new @value.dup
  end

  def to_pdx				
		@value
  end
	
	def to_s
		@value.to_s
	end
end