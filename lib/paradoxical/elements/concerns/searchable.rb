module Paradoxical::Elements::Concerns::Searchable
  extend ActiveSupport::Concern
  
  def search search
    if search.is_a? String then
      self.send :__search, Paradoxical::Search.parse( search )
    elsif search.is_a? Array and search.all? do |r| r.is_a? Paradoxical::Search::Rule end then
      self.send :__search, search
    else
      raise ArgumentError.new( "expected String or Array of Paradoxical::Search::Rule objects")
    end 
  end
  
  def find_all search=nil, &block
    if search.nil? and block.nil? then
      self.to_enum :find_all
    elsif search.nil? then
      @list.find &block
    elsif search.is_a? String then
      self.send :__search, Paradoxical::Search.parse( search )
    elsif search.is_a? Array and search.all? do |r| r.is_a? Paradoxical::Search::Rule end then
      self.send :__search, search
    else
      raise ArgumentError.new( "expected String or Array of Paradoxical::Search::Rule objects")
    end
  end

  def find search=nil, &block
    if search.nil? and block.nil? then
      self.to_enum :find
    elsif search.nil? then
      @list.find &block
    elsif search.is_a? String then
      self.send :__find, Paradoxical::Search.parse( search )
    elsif search.is_a? Array and search.all? do |r| r.is_a? Paradoxical::Search::Rule end then
      self.send :__find, search
    else
      raise ArgumentError.new( "expected String or Array of Paradoxical::Search::Rule objects")
    end
  end
  
  private
  
  def __find rules
    rule = rules.first
    rules = rules[1..-1]
  
    objects = rule.objects_for( self )
  
    return objects.find do |object| rule.matches? object end if rules.empty? 

    matches = objects.select do |object| rule.matches? object end

    matches.each do |match| 
      result = match.send :__find, rules 

      return result unless result.nil?
    end
  
    nil
  end
  
  def __search rules
    rule = rules.first
    rules = rules[1..-1]
    
    objects = rule.objects_for( self )
    
    matches = objects.select do |object| rule.matches? object end

    return matches if rules.empty?

    result = matches.map do |match| match.send :__search, rules end
      
    result.flatten.uniq do |obj| obj.object_id end
  end
end