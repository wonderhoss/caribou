require_relative '../../utils/aws_helper.rb'
require_relative '../../utils/keyvalparse'
require 'minitest/autorun'

class TestAwsHelper < Minitest::Unit::TestCase

  @@creds = KeyValueParser.parseFile("../config/aws.cfg")
  @@regions = ["eu-west-1", "ap-southeast-1", "ap-southeast-2", "eu-central-1", "ap-northeast-2", "ap-northeast-1", "us-east-1", "sa-east-1", "us-west-1", "us-west-2"]
  
  def test_list_regions
    regions = AwsHelper::listAwsRegions(@@creds[:awskeyid],@@creds[:awskey])
    regions.wont_be_empty
    regions.sort.must_equal @@regions.sort
  end
  
  def test_valid_region
    @@regions.each {|region| assert AwsHelper::verifyAwsRegion(@@creds[:awskeyid],@@creds[:awskey], region)}
    assert !AwsHelper::verifyAwsRegion(@@creds[:awskeyid],@@creds[:awskey], "some-region-1")
  end
  
end