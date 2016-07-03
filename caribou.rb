require_relative 'utils/parameter_parser.rb'
require_relative 'utils/aws_helper.rb'
require_relative 'utils/chef_provision_helper.rb'
require_relative 'utils/verbose.rb'

include Verbose

begin
  puts
  puts 'CARIBOU'
  puts '-------'
  puts
  ARGV.unshift '-h' if ARGV.empty?

  @options = AwsParser.parse(ARGV)
  if ARGV.empty? 0
    STDERR.puts 'No command given. Try --help'
    exit 1
  elsif ARGV.length > 1
    STDERR.puts "Unknown command '#{ARGV.join(' ')}'"
    exit 1
  end
  @command = ARGV[0]

  @verbose = @options[:verbose]

  logv("Running command #{@command} with config:\n#{@options}")
  puts

  @options[:basedir] = File.expand_path(File.dirname(__FILE__))

  helper = AwsHelper.new(@options)
  chef_helper = ChefHelper.new(@options)
  case @command
  when 'list'
    puts 'Available AWS Regions:'
    regions = helper.listAwsRegions
    puts 'Failed to get regions from AWS' if regions.nil?
    regions.each { |region| puts region }
    exit
  when 'getsgid'
    puts 'Default Security Group:'
    id = helper.getSecurityGroupId(@options[:securitygroup_name])
    puts "Name: #{@options[:securitygroup_name]}"
    puts "ID:   #{id}"
    exit
  when 'deploy_master'
    puts 'Deploying Caribou Master Node'
    ip = helper.deployMaster(@options[:securitygroup_name],
                             @options[:key_name],
                             @options[:master_instance_type],
                             @options[:master_image_id],
                             @options[:keymaterial])
    puts "Master Node successfully deployed with IP: #{ip}"
  when 'master_status'
    puts helper.masterStatus
  when 'shutdown'
    puts 'Shutting down Caribou Cluster'
    puts
    helper.shutdown
  when 'update-chef-repo'
    node = helper.findMasterNode[0]
    if node.nil?
      puts 'ERROR: Master node not running'
      exit 1
    end
    puts 'Uploading chef repo to server'
    puts
    chef_helper.transfer_chef_repo(node.public_ip_address, @options[:key_name])
  when 'deploy_environment'
    puts "Deploying Environment #{@options[:environment_name]}"
    puts
    helper.deployEnvironment(@options[:environment_name])
  else
    STDERR.puts "Unknown command '#{@command}'"
    exit 1
  end
rescue KeyValueParser::ParseError => fe
  puts fe.to_s
rescue OptionParser::ParseError => e
  puts e.to_s
  exit 1
end
