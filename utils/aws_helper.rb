require 'aws-sdk'

class AwsHelper
  
  class AwsHelperException < Exception; end
  
  def initialize(options = {})
    if !options.has_key?(:key)
      raise ArgumentError.new("AWS Key ID required")
    elsif !options.has_key?(:secret)
      raise ArgumentError.new("AWS secret key required")
    end
    
    @region = options.fetch(:region, "us-east-1")
    Aws.use_bundled_cert!
    @credentials = Aws::Credentials.new(options[:key], options[:secret])
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
  
  def to_s
    return "AWS Helper with key ID #{@credentials.access_key_id} in region #{@region}"
  end
  
end