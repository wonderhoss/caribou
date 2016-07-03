# Simple Key/Value Parser for reading config file
module KeyValueParser
  class ParseError < ArgumentError; end

  def self.parse_file(filename)
    raise ParseError.new("#{filename} does not exist.") unless File.exist?(filename)
    raise ParseError.new("#{filename} is not readable.") unless File.readable?(filename)
    options = File.open(filename) do |open_file|
      opts = {}
      lines = open_file.readlines
      lines.each_with_index do |line, num|
        next if line =~ /^\s*$/
        next if line =~ /^#.*$/
        raise ParseError.new("Error parsing config file: Not a key/value pair at line #{num + 1}") unless
          line.include?('=')

        line_tokens = line.split('=', 2)
        optionkey = line_tokens[0].strip
        optionvalue = line_tokens[1].strip
        opts[optionkey.to_sym] = optionvalue
      end
      opts
    end
    options
  end
end
