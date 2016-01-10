require 'optparse'
require './keyvalparse'
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
    
    verifyAwsRegion unless @options[:awsregion] == 'us-east-1'
    
    @options
  end

  def self.verifyAwsRegion
    puts "Checking for valid AWS region"
    getAwsRegions.each do |region|
      return if @options[:awsregion] == region[:region_name]
    end
    raise OptionParser::ParseError.new("Region #{@options[:awsregion]} is not a valid AWS region.")
  end

  def self.getAwsRegions
    begin
      Aws.use_bundled_cert!
      credentials = Aws::Credentials.new(@options[:awskeyid], @options[:awskey])
      ec2 = Aws::EC2::Client.new(credentials: credentials, region: 'us-east-1')
      return ec2.describe_regions.regions
    rescue Aws::Errors::ServiceError => e
      puts "Failed to connect to AWS: #{e}"
    end
  end

  begin
    opts = Parser.parse(ARGV)
    puts "DEBUG: Config found: #{opts}"
    if @options[:list]
        puts "Available AWS Regions:"
        regions = Parser.getAwsRegions
        regions.each {|region| puts region[:region_name]}
    end
    
  rescue OptionParser::ParseError => e
    puts "#{e}"
    exit 1
  rescue KeyValueParser::ParseError => fe
    puts "#{fe}"
  end
end