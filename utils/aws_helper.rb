require 'aws-sdk'
require_relative 'verbose.rb'
require 'netaddr'
require 'open-uri'

class AwsHelperException < Exception; end

class AwsHelper
 
  include Verbose
  
  SECURITY_GROUP_DEFAULT = "Caribou Default"
  
  def initialize(options = {})
    @verbose = options[:verbose]
    
    if !options.has_key?(:awskey_id)
      raise ArgumentError.new("AWS Key ID required")
    elsif !options.has_key?(:awskey)
      raise ArgumentError.new("AWS secret key required")
    end
    
    @region = options.fetch(:awsregion, "us-east-1")
    Aws.use_bundled_cert!
    @credentials = Aws::Credentials.new(options[:awskey_id], options[:awskey])
    logv "INIT: Credentials valid? #{@credentials.set?}"
    @ec2 = Aws::EC2::Client.new({credentials: @credentials, region: @region})
  end
  
  def verifyAwsRegion(a_region)
    listAwsRegions.each do |region|
      return true if a_region == region
    end
    return false
  end

  def listAwsRegions
    begin
      regions =  @ec2.describe_regions.regions
      return regions.map{ |region| region[:region_name]}
    rescue Aws::Errors::ServiceError => e
      logv e
      raise AwsHelperException.new(e)
    end
  end
  
  def getSecurityGroupId(name = SECURITY_GROUP_DEFAULT)
    begin
      result = @ec2.describe_security_groups({
        group_names: [name]
      })
      group_id = result.security_groups[0].group_id
      group = Aws::EC2::SecurityGroup.new(group_id, {client: @ec2})
      logv "Existing group found\n"
      public_ip = open('http://whatismyip.akamai.com').read
      public_ip << "/32"
      logv "Public IP queried from Akamai: #{public_ip}\n\n"
      logv "Ingress Permissions on existing group:\n"
      ssh_in_allowed = false
      group.ip_permissions.each do |permission|
        permission.ip_ranges.each do |range|
          cidr = NetAddr::CIDR.create(range.cidr_ip)
          if permission.ip_protocol == 'tcp' && permission.from_port <= 22 && permission.to_port >= 22 && (range.cidr_ip == public_ip || cidr.contains?(public_ip))
            logv "#{range.cidr_ip} (#{permission.ip_protocol}) #{permission.from_port} - #{permission.to_port} *"
            ssh_in_allowed = true
          else
            logv "#{range.cidr_ip} (#{permission.ip_protocol}) #{permission.from_port} - #{permission.to_port}"
          end
        end
      end
      logv
      logv "Existing group allows SSH in? #{ssh_in_allowed}"
      if !ssh_in_allowed
        puts "Existing group does not allow SSH in from this IP. Adding rule."
        group.authorize_ingress({
          cidr_ip: public_ip,
          from_port: 22,
          to_port: 22,
          ip_protocol: "tcp"
        })
      end      
      return group_id
    rescue Aws::Errors::ServiceError => e
      logv "AWS Error during Security Group lookup with code #{e.code}"
      if e.code != "InvalidGroupNotFound"
        puts "Error: #{e}"
      else
        logv "Caribou Default Security Group does not exist."
        begin
          logv "Creating Caribou Default Security Group."
          result = @ec2.create_security_group({
            group_name: name,
            description: "Created from Ruby SDK"
          })
          group_id = result.data.group_id
          @ec2.create_tags({
            resources: [ group_id ],
            tags: [
              {
                key: "application",
                value: "caribou"
              }
            ]
          })
          group = Aws::EC2::SecurityGroup.new(group_id, {client: @ec2})
          group.authorize_ingress({
            cidr_ip: public_ip,
            from_port: 22,
            to_port: 22,
            ip_protocol: "tcp"
          })
          logv "New group #{name} created with id #{group_id}\nGroup tagged with \"application:caribou\"."
          return group_id
        rescue Aws::Errors::ServiceError => e
          puts "Failed to create security group:"
          puts e
        end
      end
    end
  end
  
  def to_s
    return "AWS Helper with key ID #{@credentials.access_key_id} in region #{@region}"
  end
  
end