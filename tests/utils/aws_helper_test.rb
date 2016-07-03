require_relative '../../utils/aws_helper.rb'
require_relative '../../utils/keyvalparse'
require 'minitest/autorun'

# Tests for the AWS Helper class
class TestAwsHelper < Minitest::Spec
  @@creds = KeyValueParser.parse_file("#{File.dirname(__FILE__)}/../config/aws.cfg")
  @@regions = ['eu-west-1',
               'ap-southeast-1',
               'ap-south-1',
               'ap-southeast-2',
               'eu-central-1',
               'ap-northeast-2',
               'ap-northeast-1',
               'us-east-1',
               'sa-east-1',
               'us-west-1',
               'us-west-2']
  @@helper = AwsHelper.new({ awskey_id: @@creds[:awskey_id], awskey: @@creds[:awskey] })

  def test_init
    assert @@helper.instance_of?(AwsHelper)
  end

  def test_list_regions
    regions = @@helper.listAwsRegions
    regions.wont_be_empty
    regions.sort.must_equal @@regions.sort
  end

  def test_valid_region
    @@regions.each { |region| assert @@helper.verifyAwsRegion(region) }
    assert !@@helper.verifyAwsRegion('some-region-1')
  end

  def test_to_s
    assert @@helper.to_s == 'AWS Helper with key ID AKIAIGCXXZSJQZ4IZN5A in region us-east-1'
  end
end
