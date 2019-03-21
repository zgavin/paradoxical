module Paradoxical::Elements::Concerns::Searchable
  extend ActiveSupport::Concern
  
  def search search_string
    self.send :__search, Paradoxical::Search.parse( search_string ) 
  end
  
  def find_all search_string=nil, &block
    if search_string.nil? and block.nil? then
      self.to_enum :find_all
    elsif search_string.nil? then
      @list.find &block
    else
      self.send :__search, Paradoxical::Search.parse( search_string ) 
    end
  end

  def find search_string=nil, &block
    if search_string.nil? and block.nil? then
      self.to_enum :find
    elsif search_string.nil? then
      @list.find &block
    else
      self.send :__find, Paradoxical::Search.parse( search_string )
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