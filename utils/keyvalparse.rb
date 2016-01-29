module KeyValueParser
  
  class ParseError < ArgumentError; end
    
  def self.parseFile (filename)
    if !File.exists?(filename)
      raise ParseError.new("#{filename} does not exist.")
    elsif !File.readable?(filename)
      raise ParseError.new("#{filename} is not readable.")
    else
      options = File.open(filename) do |open_file|
        opts = Hash.new
        lines = open_file.readlines
        lines.each_with_index do |line, num|
          next if line.match(/^\s*$/)
          next if line.match(/^#.*$/)
          raise ParseError.new("Error parsing config file: Not a key/value pair at line #{num+1}") unless line.include?("=")
          
          line_tokens = line.split("=",2)
          optionkey = line_tokens[0].strip
          optionvalue = line_tokens[1].strip
          opts[optionkey.to_sym] = optionvalue
        end
        opts
      end
      return options
    end
  end
  
end
