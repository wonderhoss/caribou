require 'aws-sdk'
require_relative 'verbose.rb'

class AwsHelper
 
  include Verbose
  
  class AwsHelperException < Exception; end
  
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
      raise AwsHelperException(e)
    end
  end
  
  def getSecurityGroupId(name = SECURITY_GROUP_DEFAULT)
    begin
      result = @ec2.describe_security_groups({
        group_names: [name]
      })
      return result.security_groups[0].group_id
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