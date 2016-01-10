require 'optparse'
require './keyvalparse'

module Parser
  
  def self.parse(args)
    options = Hash.new
    
    OptionParser.new do |opts|
      opts.banner = "Usage: #{$0} [options]"
      opts.separator ""
      opts.separator "Specific options:"
      
      opts.on("-4", "--four TOKEN", "Some bullshit I made up with TOKEN") do |token|
        options[:four] = token
      end
      
      opts.on("-f", "--cfgfile FILE", "Load configuration from FILE") do |configfile|
        fileconfig = KeyValueParser.parseFile(configfile)
        options = fileconfig.merge!(options)
      end
    end.parse!(args)
    options
  end

  begin
    opts = Parser.parse(ARGV)
    puts "Config found: #{opts}"
  rescue OptionParser::ParseError => e
    puts "#{e}"
    exit 1
  rescue KeyValueParser::ParseError => fe
    puts "#{fe}"
  end
end