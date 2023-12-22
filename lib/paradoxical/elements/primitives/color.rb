class Paradoxical::Elements::Primitives::Color
  def initialize value
		@value = value
  end

  def dup
		self.class.new @value.dup
  end
	
  def to_pdx				
		value
  end
	
	def to_s
		value.to_s
	end
	
	def type
		maybe_parse!
		@type 
	end
	
	def colors
		maybe_parse!
		@colors
	end
	
	def whitespace
		maybe_parse!
		@whitespace
	end
	
	def rgb?
		type == "rgb"
	end
	
	def hsv?
		type == "hsv"
	end
	
	def justify!
		if rgb? then
			@whitespace = [nil, *colors.map do |c| " " * (4 - c.length) end, nil]
		else
			@whitespace = []
			@colors = @colors.map do |v| '%.3f' % v.to_f end 
		end
		
		@value = nil
		
		self
	end
	
	# https://en.wikipedia.org/wiki/HSL_and_HSV#From_RGB
	def hsv!
		return self if hsv?
		
		r, g, b = @colors.map do |c| c.to_i / 255.0 end

	  x_max = [r, g, b].max
	  x_min = [r, g, b].min
	  
	  v = x_max 
		
		c = x_max - x_min
		

		h = if c == 0 then
			0
		elsif v == r then
			((g - b) / c) 
		elsif v == g then
			((b - r) / c) + 2
		elsif v == b then
			((r - g) / c) + 4
		end
		
		h /= 6 
		
		h += 1 if h < 0
		
		s = if v == 0 then
			0
		else
			c / v
		end
					

	  @colors = [h, s, v].map do |v| '%.3f' % v end
			
		@type = "hsv"
		
		@value = nil
		
		self
	end
	
	
	# https://en.wikipedia.org/wiki/HSL_and_HSV#HSV_to_RGB
	def rgb!
		return self if rgb?
		
	  h, s, v = @colors.map(&:to_f)
		
		c = v * s
		
		h_prime = (h * 6) % 6
		
		x = c * (1 - ((h_prime % 2) - 1).abs)
		
		r1, g1, b1 = if h_prime >= 0 and h_prime < 1 then 
			[c, x, 0]
		elsif h_prime >= 1 and h_prime < 2
			[x, c, 0] 
		elsif h_prime >= 2 and h_prime < 3
			[0, c, x] 
		elsif h_prime >= 3 and h_prime < 4
			[0, x, c]
		elsif h_prime >= 4 and h_prime < 5
			[x, 0, c] 
		elsif h_prime >= 5 and h_prime < 6
			[c, 0, x]
		end
		
		m = v - c
		
		@colors = [r1, g1, b1].map do |c| ((c + m) * 255).to_i.to_s end
			
		@type = "rgb"
			
		@value = nil	
			
		self
	end
		
	private 
	
	def value
		@value ||= begin
			value = type.dup
			
			value << (whitespace[0] or " ")
			value << "{"
			
			3.times do |i|
				value << (whitespace[1 + i] or " ")
				value << colors[i].to_s
			end
			
			value << (whitespace[4] or " ")
			value << "}"
			
			value
		end
	end
	
	def maybe_parse!
		return unless @type.nil? or @colors.nil? or @whitespace.nil?
		
		matches = @value.match(/^(?<type>rgb|hsv)(?<ws_0>\s*)\{(?<ws_1>\s*)(?<color_0>\d+\.?\d*)(?<ws_2>\s+)(?<color_1>\d+\.?\d*)(?<ws_3>\s+)(?<color_2>\d+\.?\d*)(?<ws_4>\s*)\}$/)
		
		@type = matches[:type]
		@colors = 3.times.map do |i| matches["color_#{i}".to_sym] end
		@whitespace = 5.times.map do |i| matches["ws_#{i}".to_sym] end
	end
end