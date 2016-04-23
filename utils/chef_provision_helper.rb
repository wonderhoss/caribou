require_relative 'verbose.rb'
require 'aws-sdk'
require 'net/ssh'

#TODO: Error handling on bucket check and file upload

class ChefHelper

  # Mix in verbose debug logging 
  include Verbose
  
  #
  # Sets up the AWS client
  #
  def initialize(options = {})
    @verbose = options[:verbose]
    @region = options.fetch(:awsregion, "us-east-1")
    @options = options
    if !options.has_key?(:awskey_id)
      raise ArgumentError.new("AWS Key ID required")
    elsif !options.has_key?(:awskey)
      raise ArgumentError.new("AWS secret key required")
    end
    
    @region = options.fetch(:awsregion, "us-east-1")
    Aws.use_bundled_cert!
    @credentials = Aws::Credentials.new(options[:awskey_id], options[:awskey])
    logv "INIT: Credentials valid? #{@credentials.set?}"
    @s3 = Aws::S3::Client.new({credentials: @credentials, region: @region})
  end
  
  def upload_file(prefix, file)
    raise ArgumentError.new("Cannot read #{file}") if !File.readable?(file)
    if find_file("vendor", "file")
      logv "vendor/#{file} already present in S3 bucket"
      return
    else
      begin
        resource = Aws::S3::Resource.new({client: @s3})
        object = resource.bucket(@options[:s3_bucket]).object("#{prefix}/#{file.split("/").last}")
        object.upload_file(file)
      rescue Aws::Errors::ServiceError => e
        puts "FAIL: Failed to upload file: #{e}"
      end
    end
  end
  
  def find_file(prefix, filename)
    return false unless find_bucket
    list = @s3.list_objects({
      bucket: @options[:s3_bucket],
      prefix: prefix
    })
    return list.contents.any? {|o| o[:key] == "#{prefix}/#{filename}"}
  end
  
  def find_bucket
    begin
      resp = @s3.head_bucket({bucket: @options[:s3_bucket]})
      puts "Bucket found"
      return true
    rescue Aws::S3::Errors::Forbidden
      puts "Bucket name #{@options[:s3_bucket]} unavailable"
      return false
    rescue Aws::S3::Errors::NotFound
      puts "Bucket not found, creating..."
      resp = @s3.create_bucket({bucket: @options[:s3_bucket]})
      puts "...created"
      return true
    end
  end
    
  def delete_bucket
    resp = @s3.delete_bucket({bucket: @options[:s3_bucket]})
    puts resp
  end
    
  def get_cloudinit_script
    template = File.read("#{@options[:basedir]}/infra/scripts/deploy-chef-template.sh")
    vals = {key: @options[:awskey_id], secret: @options[:awskey], region: @region, caribou_folder: @options[:s3_bucket], chef_email: @options[:chef_email], chef_password: @options[:chef_password]}
    script = template % vals
    return script
  end
  
  #TODO: Handle images with users other than ubuntu
  def cloud_init_complete?(instance_ip, key_name)
    try = 1
    raise ArgumentError.new("Keyfile #{key_name}.pem not found") unless File.readable?("#{@options[:basedir]}/#{key_name}.pem")
    keys = File.read("#{@options[:basedir]}/#{key_name}.pem")
    begin
      Net::SSH.start(instance_ip, "ubuntu", :keys => [], :key_data => keys, :keys_only => true) do |ssh|
        result = ssh.exec!("sudo bash -c \"if test -e /root/cloud-init.complete; then echo \"complete\"; else echo \"pending\"; fi\"")
        return true if result.chomp == "complete"
        return false
      end
    rescue Net::SSH::ConnectionTimeout
      logv "SSH connection timeout. Attempt (#{try}/5)."
      try +=1
      retry if try < 6
    end
  end
    
end