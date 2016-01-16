require_relative 'utils/parameter_parser.rb'
require_relative 'utils/aws_helper.rb'

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
  if ARGV.length == 0
    STDERR.puts "No command given. Try --help"
    exit 1
  elsif ARGV.length > 1
    STDERR.puts "Unknown command '#{ARGV.join(" ")}'"
    exit 1
  end
  @command = ARGV[0]
  
  logv("Running command #{@command} with config:\n#{@options}")
  puts

  helper = AwsHelper.new({
    key: @options[:awskey_id],
    secret: @options[:awskey]
  })

  case @command
  when "list"
    puts "Available AWS Regions:"
    regions = helper.listAwsRegions
    regions.each {|region| puts region}
    exit
  when "getsgid"
    puts "Default Security Group:"
    id = helper.getSecurityGroupId(@options[:securitygroup_name])
    puts "Name: #{@options[:securitygroup_name]}"
    puts "ID:   #{id}"
    exit
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