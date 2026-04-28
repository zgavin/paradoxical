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

	def hsv360?
		type == "hsv360"
	end

	def cylindrical?
		type == "cylindrical"
	end

	def hex?
		type == "hex"
	end
	
	def justify!
		if rgb? && colors.length == 3 then
			@whitespace = [nil, *colors.map do |c| " " * (4 - c.length) end, nil]
		elsif hsv? && colors.length == 3 then
			@whitespace = []
			@colors = @colors.map do |v| '%.3f' % v.to_f end
		else
			# hsv360 / cylindrical / hex / 4-component (alpha) — each
			# would need its own justification rule. Phase 8 follow-up.
			raise NotImplementedError, "justify! for #{type} (#{colors.length}-component) is a phase 8 follow-up"
		end

		@value = nil

		self
	end
	
	# https://en.wikipedia.org/wiki/HSL_and_HSV#From_RGB
	def hsv!
		return self if hsv?

		unless rgb? && colors.length == 3
			raise NotImplementedError, "#{type} (#{colors.length}-component) -> hsv conversion is a phase 8 follow-up"
		end

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

		unless hsv? && colors.length == 3
			raise NotImplementedError, "#{type} (#{colors.length}-component) -> rgb conversion is a phase 8 follow-up"
		end

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

			colors.each_with_index do |c, i|
				value << (whitespace[1 + i] or " ")
				value << c.to_s
			end

			value << (whitespace[colors.length + 1] or " ")
			value << "}"

			value
		end
	end

	def maybe_parse!
		return unless @type.nil? or @colors.nil? or @whitespace.nil?

		# Two body shapes:
		#   - 3-or-4-component:  rgb | hsv | hsv360 | cylindrical
		#   - 1-component hex literal:  hex { 0x...... }
		# Components allow optional leading `-` (cylindrical uses it for
		# angles/heights; rgb/hsv don't but the regex is shared).
		if (m = @value.match(/^(?<type>hex)(?<ws_open>\s*)\{(?<ws_1>\s*)(?<color_0>0x[0-9a-fA-F]+)(?<ws_close>\s*)\}$/))
			@type = m[:type]
			@colors = [m[:color_0]]
			@whitespace = [m[:ws_open], m[:ws_1], m[:ws_close]]
		else
			m = @value.match(/^(?<type>hsv360|rgb|hsv|cylindrical)(?<ws_open>\s*)\{(?<ws_1>\s*)(?<color_0>-?\d+\.?\d*)(?<ws_2>\s+)(?<color_1>-?\d+\.?\d*)(?<ws_3>\s+)(?<color_2>-?\d+\.?\d*)(?:(?<ws_pre_alpha>\s+)(?<color_3>-?\d+\.?\d*))?(?<ws_close>\s*)\}$/)
			@type = m[:type]
			@colors = [m[:color_0], m[:color_1], m[:color_2], m[:color_3]].compact
			@whitespace = [m[:ws_open], m[:ws_1], m[:ws_2], m[:ws_3]]
			@whitespace << m[:ws_pre_alpha] if m[:color_3]
			@whitespace << m[:ws_close]
		end
	end
end