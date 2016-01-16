require 'aws-sdk'

class AwsHelper
  
  class AwsHelperException < Exception; end
  
  def self.verifyAwsRegion(key, secret, a_region)
    listAwsRegions(key, secret).each do |region|
      return true if a_region == region
    end
    return false
  end

  def self.listAwsRegions(key, secret)
    begin
      Aws.use_bundled_cert!
      credentials = Aws::Credentials.new(key, secret)
      ec2 = Aws::EC2::Client.new(credentials: credentials, region: 'us-east-1')
      regions =  ec2.describe_regions.regions
      return regions.map{ |region| region[:region_name]}
    rescue Aws::Errors::ServiceError => e
      raise AwsHelperException(e)
    end
  end
  
end