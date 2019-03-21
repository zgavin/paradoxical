class Paradoxical::Elements::Primitives::Date
  # We don't impersonate dates because none of the paradox games use a gregorian calendar.
  # Stellaris has 360 day year with 12 months of 30 days each.
  # The other games use a modified julian calendar with no leap years
  # There's been no need to actually manipulate dates so all we need is the raw value for now
  
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