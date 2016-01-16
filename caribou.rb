require_relative 'utils/parameter_parser.rb'

def logv(message)
    puts message if @options[:verbose]
end

begin
  puts
  puts "CARIBOU"
  puts "-------"
  puts
  if ARGV.empty?
    ARGV.unshift "-h"
  end
  
  @options = AwsParser.parse(ARGV)
  if ARGV.length > 1
    STDERR.puts "Unknown command '#{ARGV.join(" ")}'"
    exit 1
  end
  @command = ARGV[0]
  
  logv("Running command #{@command} with config:\n#{@options}")
  puts

  case @command
  when "list"
    puts "Available AWS Regions:"
    regions = AwsHelper::listAwsRegions(@options[:awskeyid],@options[:awskey])
    regions.each {|region| puts region}
  else
    STDERR.puts "Unknown command '#{@command}'"
    exit 1
  end

rescue OptionParser::ParseError => e
  puts "#{e}"
  exit 1
rescue KeyValueParser::ParseError => fe
  puts "#{fe}"
end