require_relative 'verbose.rb'
require 'aws-sdk'
require 'net/ssh'
require 'net/scp'

# TODO: Error handling on bucket check and file upload
# Helper class for performing provisioning scripts
class ChefHelper
  # Mix in verbose debug logging
  include Verbose

  #
  # Sets up the AWS client
  #
  def initialize(options = {})
    @verbose = options[:verbose]
    @region = options.fetch(:awsregion, 'us-east-1')
    @options = options
    raise ArgumentError.new('AWS Key ID required') unless options.key?(:awskey_id)
    raise ArgumentError.new('AWS secret key required') unless options.key?(:awskey)

    @region = options.fetch(:awsregion, 'us-east-1')
    Aws.use_bundled_cert!
    @credentials = Aws::Credentials.new(options[:awskey_id], options[:awskey])
    @s3 = Aws::S3::Client.new({ credentials: @credentials, region: @region })
  end

  def upload_file(prefix, file)
    raise ArgumentError.new("Cannot read #{file}") unless File.readable?(file)
    if find_file('vendor', 'file')
      logv "vendor/#{file} already present in S3 bucket"
      return
    else
      begin
        resource = Aws::S3::Resource.new({ client: @s3 })
        object = resource.bucket(@options[:s3_bucket]).object("#{prefix}/#{file.split('/').last}")
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
    list.contents.any? { |o| o[:key] == "#{prefix}/#{filename}" }
  end

  def find_bucket
    @s3.head_bucket({ bucket: @options[:s3_bucket] })
    return true
  rescue Aws::S3::Errors::Forbidden
    puts "Bucket name #{@options[:s3_bucket]} unavailable"
    return false
  rescue Aws::S3::Errors::NotFound
    puts 'Bucket not found, creating...'
    @s3.create_bucket({ bucket: @options[:s3_bucket] })
    puts '...created'
    return true
  end

  def delete_bucket
    resp = @s3.delete_bucket({ bucket: @options[:s3_bucket] })
    puts resp
  end

  def master_cloudinit_script
    template = File.read("#{@options[:basedir]}/infra/scripts/deploy-chef-template.sh")
    vals = { key:            @options[:awskey_id],
             secret:         @options[:awskey],
             region:         @region,
             caribou_folder: @options[:s3_bucket],
             chef_email:     @options[:chef_email],
             chef_password:  @options[:chef_password] }
    script = template % vals
    script
  end

  def node_cloudinit_script(master_ip, nodename, role)
    template = File.read("#{@options[:basedir]}/infra/scripts/init-node-template.sh")
    vals = { key:            @options[:awskey_id],
             secret:         @options[:awskey],
             region:         @region,
             caribou_folder: @options[:s3_bucket],
             nodename:       nodename,
             master_ip:      master_ip,
             role:           role }
    script = template % vals
    script
  end

  # TODO: Handle images with users other than ubuntu
  def cloud_init_complete?(instance_ip, key_name)
    try = 1
    raise ArgumentError.new("Keyfile #{key_name}.pem not found") unless
      File.readable?("#{@options[:basedir]}/#{key_name}.pem")
    keys = File.read("#{@options[:basedir]}/#{key_name}.pem")
    begin
      Net::SSH.start(instance_ip, 'ubuntu', { keys: [], key_data: keys, keys_only: true }) do |ssh|
        result = ssh.exec!("sudo bash -c \"if test -e /root/cloud-init.complete;\n\
  then echo \"complete\"; else echo \"pending\";\n\
fi\"")
        return true if result.chomp == 'complete'
        return false
      end
    rescue => e
      logv "SSH connection failed. Attempt (#{try}/10)."
      logv e
      try += 1
      retry if try < 11
    end
  end

  def transfer_chef_repo(instance_ip, key_name)
    raise ArgumentError.new("Keyfile #{key_name}.pem not found") unless
      File.readable?("#{@options[:basedir]}/#{key_name}.pem")
    keys = File.read("#{@options[:basedir]}/#{key_name}.pem")
    Net::SSH.start(instance_ip, 'ubuntu', { keys: [], key_data: keys, keys_only: true }) do |ssh|
      ssh.scp.upload!("#{@options[:basedir]}/chef-repo", '/home/ubuntu', { recursive: true })
      output = ssh.exec!('if [ -e /home/ubuntu/caribou.pem ];\n\
  then mv /home/ubuntu/caribou.pem /home/ubuntu/chef-repo/.chef;\n\
fi')
      output.each_line do |line|
        logv "  > #{line}"
      end
      command = "if [ -e /home/ubuntu/caribou-master.crt ];\n\
  then mkdir /home/ubuntu/chef-repo/.chef/trusted_certs;\n\
  mv /home/ubuntu/caribou-master.crt /home/ubuntu/chef-repo/.chef/trusted_certs/caribou-master.crt;\n\
fi"
      output = ssh.exec!(command)
      output.each_line do |line|
        logv "  > #{line}"
      end
      output = ssh.exec!('cd /home/ubuntu/chef-repo; knife upload cookbooks/*; knife role from file roles/*')
      output.each_line do |line|
        logv "  > #{line}"
      end
    end
  end
end
