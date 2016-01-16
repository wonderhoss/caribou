require 'optparse'
require_relative './keyvalparse'
require_relative './aws_helper'
require 'aws-sdk'

module AwsParser

  #Set Defaults
  COMMANDS = ['list']
  @options =  {:awsregion => "us-east-1"}
  
  def self.parse(args)

    #Setup option parser
    OptionParser.new do |opts|
      opts.banner = "Usage: #{$0} <command> [options]"
      opts.separator ""
      opts.separator "Command can be one of: #{COMMANDS.join(" ")}"
      opts.separator ""
      opts.separator "Specific options:"
      
      opts.on("-k", "--awskeyid ID", "The AWS key ID to use") do |id|
        @options[:awskey_id] = id
      end
      
      opts.on("-r", "--region REGION", "The AWS region to use") do |region|
        @options[:awsregion] = region
      end
      
      opts.on_tail("-f", "--cfgfile FILE", "Load configuration from FILE") do |configfile|
        fileconfig = KeyValueParser.parseFile(configfile)
        @options = fileconfig.merge!(@options)
      end
      
      opts.on_tail("-v", "--verbose", "Show verbose logging") do |v|
        @options[:verbose] = v
      end
      
      opts.on_tail("-h", "--help", "Show this message") do
        puts opts
        exit
      end

      # Another typical switch to print the version.
      opts.on_tail("--version", "Show version information") do
        File.open(File.expand_path("./VERSION", File.dirname(__FILE__)), "r") do |vfile|
          puts ("Caribou version: #{vfile.read}")
          puts
          exit
        end
        exit
      end
    end.parse!(args)
    
    #Verify parsed options
    if !@options.has_key?(:awskeyid)
        raise OptionParser::MissingArgument.new("AWS Key ID is required.")
    elsif !@options.has_key?(:awskey)
      print "Please enter AWS secret key: "
      @options[:awskey] = gets.chomp
    end
    
    unless @options[:awsregion] == 'us-east-1'
      puts "Validating AWS region"
      raise OptionParser::ParseError.new("Region #{@options[:awsregion]} is not a valid AWS region.") unless verifyAwsRegion(@options[:awskeyid], @options[:awskey], @options[:awsregion])
    end
    
    @options
  end
  
end