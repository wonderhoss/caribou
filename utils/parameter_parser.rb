require 'optparse'
require './keyvalparse'
require './aws_helper'
require 'aws-sdk'

module Parser

  #Set Defaults
  @options =  {:awsregion => "us-east-1", :list => false}
  
  def self.parse(args)
    
    #Setup option parser
    OptionParser.new do |opts|
      opts.banner = "Usage: #{$0} [options]"
      opts.separator ""
      opts.separator "Specific options:"
      
      opts.on("--list-aws-regions", "Display a list of available AWS regions") do
        @options[:list] = true
      end
      
      
      opts.on("-k", "--awskeyid ID", "The AWS key ID to use") do |id|
        @options[:awskeyid] = id
      end
      
      opts.on("-r", "--region REGION", "The AWS region to use") do |region|
        @options[:awsregion] = region
      end
      
      opts.on("-f", "--cfgfile FILE", "Load configuration from FILE") do |configfile|
        fileconfig = KeyValueParser.parseFile(configfile)
        @options = fileconfig.merge!(@options)
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


  begin
    opts = Parser.parse(ARGV)
    puts "DEBUG: Config found: #{opts}"
    if @options[:list]
        puts "Available AWS Regions:"
        regions = AwsHelper::listAwsRegions(@options[:awskeyid],@options[:awskey])
        regions.each {|region| puts region}
    end
    
  rescue OptionParser::ParseError => e
    puts "#{e}"
    exit 1
  rescue KeyValueParser::ParseError => fe
    puts "#{fe}"
  end
end