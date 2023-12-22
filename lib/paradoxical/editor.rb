class Paradoxical::Editor
	class << self
		def edit path, game: nil, &block
			started_at = Time.now
			puts "Editing #{File.dirname path}"
			editor = self.new(path, game: game)
			done_parsing_at = Time.now
			puts "Parsing: #{'%.2f' % (done_parsing_at - started_at)}"
			editor.instance_exec(&block)
			editor.instance_exec do
				player = empires.first
				player.search("> &list&key-matches(/terra_incognita|hyperlane_systems|visited_objects/) &value").each(&:remove)
				empires[1..-1].flat_map do |e| e.search("> &list&key-matches(/terra_incognita|hyperlane_systems|visited_objects/) &value") end.each(&:remove)
			end
			done_editing_at = Time.now
			puts "Editing: #{'%.2f' % (done_editing_at - done_parsing_at)}" 
			editor.write
			puts "Writing: #{'%.2f' % (Time.now - done_editing_at)}"
		rescue Exception => e
			puts e.inspect
			exit
		end
	end
	
	attr_reader :path, :game, :gamestate, :meta
	
  def initialize path, game: nil
		@path = path
		@game = ( game or Paradoxical::Game.new('Stellaris') )		
		
		Zip::File.open( full_path ) do |zip_file|
			@meta = Paradoxical::Parser.parse zip_file.glob( "meta" ).first.get_input_stream.read
			# for some reason the intel manager section is not formatted correctly so we need to use a regex to fix it
		  @gamestate = Paradoxical::Parser.parse zip_file.glob( "gamestate" ).first.get_input_stream.read.gsub(/^(\d+)\s*\{$/, '\1 = {')			
		end
	end

	def write 
		# paradox really wants the intel manager section to be formatted badly
		@gamestate.search("> country > * > intel_manager > intel > &list > &list").each do |node| node.operator = "" end 
		Zip::File.open(output_path, create: true) do |zipfile|
		  zipfile.get_output_stream("meta") do |f| f.write @meta.to_pdx end
		  zipfile.get_output_stream("gamestate") do |f| f.write @gamestate.to_pdx end
		end
	end

	def full_path 
		game.user_directory.join "save games", path
	end
	
	def output_path
		basename = File.basename full_path, ".sav"
		Pathname.new(File.dirname(full_path)).join "#{basename}_edit.sav"
	end
	
	def method_missing sym, *args, **opts, &block
		@gamestate.send(sym, *args, **opts, &block)
	end
	
	{ empires: "country", systems: "galactic_object", planets: "planets > planet", leaders: "leaders", clusters: "clusters" }.each do |sym, key|
		define_method sym do 
			@gamestate.find("> #{key}").lists 
		end
	end
	
	
	def initializers 
		@initializers ||= begin
			docs = parse_files common_files "solar_system_initializers"
			docs.map do |doc| doc.lists end.flatten.map do |init| [init.key, init] end.to_h
		end
	end
		
	def swap_systems a, b, do_chain: true
		systems = [a,b].map do |i| self.systems[i] end
			
		system_a, system_b = systems
		
		coordinate_a, coordinate_b = systems.map do |s| s['coordinate'].remove end
			
		system_a.unshift coordinate_b
		system_b.unshift coordinate_a
		
		hyperlane_a, hyperlane_b = systems.map do |s| s['hyperlane'].remove end
			
		system_a['star_class'].insert_after hyperlane_b
		system_b['star_class'].insert_after hyperlane_a
		
		[[system_a, system_b], [system_b, system_a]].each do |from, to|
			to['hyperlane'].lists.map do |lane|				
				# if a system has a hyperlane to itself, then we need to swap it back (eg, ratlings might have this)
				if lane["to"].value == from.key then
					lane["to"] = to.key
				# if the two systems already have a lane, then they'll now have lanes pointing to themselves, so swap these
				elsif lane["to"].value == to.key then
					lane["to"] = from.key
				else
					other = @gamestate.find("> galactic_object > #{lane["to"].value} > hyperlane > [to=#{from.key}]")
					other["to"].value = to.key.dup
					other["length"].value = lane["length"].value.dup
				end
			end
		end
		
		%w{empire_cluster marauder_cluster precursor_1 precursor_2 precursor_3 precursor_4 precursor_5 precursor_baol_1 precursor_zroni_1}.each do |flag|
			flag_a, flag_b = systems.map do |s| s.find("> flags > #{flag}")&.remove end
			
			if flag_b then
				system_a << build do l "flags" end if system_a['flags'].nil?
				system_a['flags'] << flag_b
			end
			if flag_a then
				system_b << build do l "flags" end if system_b['flags'].nil?
				system_b['flags'] << flag_a
			end
		end
		
		[
			[a, 123456789],
			[b, a],
			[123456789, b]
		].each do |(a,b)|
			gamestate["clusters"].search("> &list > objects").each do |objects|
				value = objects.all.find do |v| v.value == a end
				next if value.nil?
				value&.value = b
				objects.sort_by! do |v| v.value end if b != 123456789
			end
		end
		
		init = initializers[system_a['initializer'].value]
		
		return [] if init.key == "pt_basic_init_01"
		
		neighbors = init.search("> neighbor_system").map do |neighbor| [a, neighbor] end
		
		return [] if neighbors.empty? 

		return neighbors unless do_chain
		
		has_flag = proc do |sys, flag| sys.present? and (sys['flags']&.properties&.map(&:key) or []).include? flag end

		eligible_systems = self.systems
			.reject do |sys| sys.key == a end
			.reject do |sys| has_flag.call sys, "empire_home_system" end
			
		
		until neighbors.empty? do
			origin, neighbor = neighbors.shift 
		
			initializer_name = neighbor["initializer"].value 
		
			source = eligible_systems.find do |sys| 
				sys["initializer"].value == initializer_name and sys["init_parent"]&.value&.to_s == origin.to_s 
			end
				
			trigger = neighbor['trigger']
			
			trigger_allowed = if trigger.nil? then
				true
			elsif %{ratling_1_2 ratling_1_3}.include? initializer_name then
				true
			elsif trigger.length == 1 and trigger["num_guaranteed_colonies"].present? then
				num_guaranteed_colonies = @gamestate.find("> galaxy > num_guaranteed_colonies").value
				operator = trigger["num_guaranteed_colonies"].operator 
				operator = "==" if operator == "="
				eval "#{num_guaranteed_colonies} #{operator} #{trigger["num_guaranteed_colonies"].value}"
			else  
				puts "warning: unhandled trigger in #{initializer_name}: #{neighbor['trigger'].to_pdx}"
				true
			end	
				
			next unless trigger_allowed
		
			eligible_systems.delete_if do |sys| sys.key == source&.key end
	
			jump_map = self.jump_map origin
		
			d = neighbor['distance']
			h = neighbor["hyperlane_jumps"]
			
			min_distance = d.present? ? d['min']&.value : 0
			max_distance = d.present? ? d['max']&.value : Float::INFINITY

			min_jumps = h.present? ? h['min']&.value : 0
			max_jumps = h.present? ? h['max']&.value : Float::INFINITY
			max_jumps = 3 if max_jumps == "@jumps"
	
			target = eligible_systems
				.reject do |sys| has_flag.call sys, "hostile_system" end
				.reject do |target| %w{neighbor_t1 neighbor_t2 neighbor_t1_first_colony neighbor_t2_second_colony}.any? do |flag| has_flag.call target, flag and not has_flag.call source, flag end end
				.map do |target| [target, distance(origin, target.key), (jump_map[target.key] or Float::INFINITY)] end
				.filter do |(target, distance, jumps)|
					next false if min_distance > distance or max_distance < distance
					next false if min_jumps > jumps or max_jumps < jumps
					true
				end
				.min_by do |(target, distance, jumps)| distance end
				&.first
				
			puts "warning: source not found for \"#{neighbor["initializer"].value}\" initializer" if source.nil?
			puts "warning: target not found for \"#{neighbor["initializer"].value}\" initializer" if target.nil?
			
			next if source.nil? or target.nil?
				
			target_init = initializers[target['initializer'].value]
				
			puts "warning: could not find existing system for \"#{neighbor["initializer"].value}\" but eligible system #{target} exists in new location" if source.nil? and target.present?
			puts "warning: moving \"#{target["initializer"].value}\" which was chained from #{target["init_parent"].value}" unless target["init_parent"].nil?
			puts "warning: moving \"#{target["initializer"].value}\" (#{target.key}) which has is_in_cluster" if target_init.find("> usage_odds > modifier is_in_cluster")

			puts "#{neighbor["initializer"].value}: #{source.key} -> #{target.key}"
		
			result = swap_systems source.key, target.key, do_chain: false
		
			neighbors.concat result
		end 
				
		return []
	rescue Exception => e
		puts "swap_systems #{a}, #{b}"
		raise e
	end
	
	def jumps a, b
		(@jumps ||= Jumps.new self).distance a,b
	end
	
	def remove_hyperlane from, to
		a,b = [from,to].map do |i| systems[i] end
		
		a.find("> hyperlane > [to=#{b.key}]").remove
		b.find("> hyperlane > [to=#{a.key}]").remove
	rescue Exception => e
		puts "remove_hypelane #{from}, #{to}"
		raise e
	end
	
	def add_hyperlane from, to
		a,b = [from,to].map do |i| self.systems[i] end
			
		distance = self.distance(from, to).floor
		[a,b].reject do |s| s["hyperlane"].present? end.each do |s| s << Paradoxical::Elements::List.new("hyperlane", []) end
		a["hyperlane"] << build do
			list false do
				to b.key.dup
				length distance
			end
		end
		
		b["hyperlane"] << build do
			list false do
				to a.key.dup
				length distance
			end
		end
	end
	
	def distance from, to
		a,b = [from,to].map do |i| self.systems[i] end
			
		x_a, x_b = [a,b].map do |n| n['coordinate']['x'].value end
		y_a, y_b = [a,b].map do |n| n['coordinate']['y'].value end
			
		( (x_a - x_b)**2 + (y_a - y_b)**2 ) ** 0.5 
	end
	
	def move id, x, y
		sys = systems[id]
		sys["coordinate"]["x"].value = x
		sys["coordinate"]["y"].value = y
	end
	
	def move_relative id, x, y
		sys = systems[id]
		sys["coordinate"]["x"].value += x
		sys["coordinate"]["y"].value += y
	end
		
	def build &block
		result = Paradoxical::Builder.new.build &block
		
		result.count == 1 and result.first or result
	end
	
	def jump_map source
		data = { }
		queue = [[systems[source], 0]]
		
		until queue.empty? do
			current, jumps = queue.shift

			break if current.nil? and queue.empty?
			next if data[current.key].present?
			
			data[current.key] = jumps
			
			jumps += 1
			current["hyperlane"]&.lists.each do |h|
				to = h["to"].value
				next if data[to].present?
				next puts "warning can't find #{to}" if systems[to].nil?
				queue.push [systems[to], jumps]
			end
		end
		
		data
	end

	#implemented as a separate class to not pollute the namespace
	class Jumps	
		class Node < Struct.new(:sys, :prev, :g, :f, :neighbors)
			def == other
				other.sys.key == self.sys.key
			end
			
			def reset!
				self.prev = nil
				self.g = Float::INFINITY
				self.f = Float::INFINITY
			end
		end
	
		attr_reader :editor, :nodes
	
		def initialize editor
			@editor = editor
			@nodes = editor.systems.map do |sys| Node.new sys end
			@nodes.each do |n|
				n.neighbors = (n.sys["hyperlane"]&.lists or []).map do |h| @nodes[h["to"].value] end
			end
		end
	
		def average_hyperlane_distance
			@average_hyperlane_distance ||= begin
			 hyperlanes = nodes.map do |n| n.sys['hyperlane']&.lists end.compact.flatten
			 total_length = hyperlanes.sum do |h| h["length"].value end
			 total_length / hyperlanes.length
			end
		end
	
		def distance from, to
			nodes.each &:reset!
			
			start, target = [from,to].map do |i| nodes[i] end
				
			return Float::INFINITY if start.neighbors.empty? or target.neighbors.empty?
		
			start.g = 0
			start.f = 0
			open_set = [start]

	    until open_set.empty? do
	      current = open_set.min do |n| n.f end 
					
				if current == target then
					length = 0
					until current.prev.nil? do
						length += 1
						current = current.prev
					end
					return length
				end
			
	      open_set.delete current
			
				current.neighbors.each do |n|
					tentative_g = current.g + 1
					if tentative_g < n.g then
						n.prev = current
						n.g = tentative_g
						n.f = tentative_g + ( editor.distance( n.sys.key, target.sys.key ) / average_hyperlane_distance )
					
						open_set.push n unless open_set.include? n
					end
				end
			end
		
			puts "no route from #{from} to #{to}" 
		
			return Float::INFINITY
		end
	end
end



	
	
	