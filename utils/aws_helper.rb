require 'aws-sdk'
require_relative 'verbose.rb'
require 'netaddr'
require 'open-uri'
require 'terminal-table'

#######################################################
#
# Main interaction point with the AWS SDK
#
#######################################################
class AwsHelper

  # Mix in verbose debug logging 
  include Verbose
  
  SECURITY_GROUP_DEFAULT = "Caribou Default"
  

  #
  # Sets up the EC2 client
  #
  def initialize(options = {})
    @verbose = options[:verbose]
    
    if !options.has_key?(:awskey_id)
      raise ArgumentError.new("AWS Key ID required")
    elsif !options.has_key?(:awskey)
      raise ArgumentError.new("AWS secret key required")
    end
    
    @newkey = options[:new_key]
    
    @region = options.fetch(:awsregion, "us-east-1")
    Aws.use_bundled_cert!
    @credentials = Aws::Credentials.new(options[:awskey_id], options[:awskey])
    logv "INIT: Credentials valid? #{@credentials.set?}"
    @ec2 = Aws::EC2::Client.new({credentials: @credentials, region: @region})
  end
  
  #
  # Gets a list of all region accessible with the AWS credentials used
  #
  def listAwsRegions
    begin
      regions =  @ec2.describe_regions.regions
      return regions.map{ |region| region[:region_name]}
    rescue Aws::Errors::ServiceError => e
      logv "AWS call failed:"
      logv e
      return nil
    end
  end
  
  
  #
  # Checks whether a given region is valid for the AWS credentials used
  #
  def verifyAwsRegion(a_region)
    regions = listAwsRegions
    return false if regions.nil?
    regions.each do |region|
      return true if a_region == region
    end
    return false
  end

  
  #
  # Queries AWS for the id of a given Security Group
  #
  def getSecurityGroupId(name = SECURITY_GROUP_DEFAULT)
    public_ip = open('http://whatismyip.akamai.com').read
    public_ip << "/32"
    begin
      result = @ec2.describe_security_groups({
        group_names: [name]
      })
      group_id = result.security_groups[0].group_id
      group = Aws::EC2::SecurityGroup.new(group_id, {client: @ec2})
      logv "Existing group found\n"
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
      if e.code != "InvalidGroupNotFound"
        logv "AWS Error during Security Group lookup with code #{e.code}"
        raise e
      else
        logv "Caribou Default Security Group does not exist."
        return createSecurityGroup(name, public_ip)
      end
    end
  end
  
  
  #
  # Queries AWS for the status of the Caribou master node
  #
  def masterStatus
    nodes = findMasterNode()
    if nodes.nil?
      table = Terminal::Table.new do |t|
        t << ['Instance ID', 'Instance Type', 'Public IP', 'State']
        t << :separator
        t.add_row [{:value => "master node not running", :alignment => :center, :colspan => 4}]
      end
    else
      table = Terminal::Table.new do |t|
        t << ['Instance ID', 'Type', 'Public IP', 'Key Name', 'State']
        t << :separator
        t.add_row [nodes[0].instance_id, nodes[0].instance_type, nodes[0].public_ip_address, nodes[0].key_name, nodes[0].state.name]
      end
    end
    return table
  end
  
  
  #
  # Deploys a new EC2 instance to use as master node
  #
  def deployMaster(security_group, keyname = nil, instance_type = "t1.micro", image_id = "ami-7b386c11", pubkey = nil)
    if keyname.nil?
      if pubkey.nil?
        if @newkey
          puts "Creating new key pair..."
          key = createKeypair()
        else
          puts "ERROR: No keypair provided and --new-key not supplied."
          puts "ERROR: Unable to deploy."
          exit 5
        end
      else
        name = "caribou_keypair_#{(Time.now.to_i).to_s(16)}"
        key = importKey(name, pubkey)
      end
    else
      begin
        logv "Looking up key pair by name"
        key_result = @ec2.describe_key_pairs(key_names: [keyname])
        logv "Key found"
        key = { name: key_result.key_pairs[0].key_name, fingerprint: key_result.key_pairs[0].key_fingerprint }
        puts "WARN: A key with the provided name already exists in AWS. Using existing key instead of public key provided." unless pubkey.nil?
      rescue Aws::EC2::Errors::ServiceError => e
        if e.code == "InvalidKeyPairNotFound"
          puts "No key pair '#{keyname}' exists."
          if pubkey.nil?
            if @newkey
              puts "Creating new key pair..."
              key = createKeypair(keyname)
            else
              puts "ERROR: No keypair provided and --new-key not supplied."
              puts "ERROR: Unable to deploy."
              exit 5
            end
          else
            key = importKey(keyname, pubkey)
          end
        end
      end
    end
    if key.nil?
      puts "ERROR: Error while configuring key pair. Aborting."
      exit 5
    end
    
    group_id = getSecurityGroupId(security_group)
    
    #ip_allocation = @ec2.allocate_address()
    #logv "Allocated IP address:"
    #table = Terminal::Table.new do |t|
    #  t << ['IP', 'Allocation ID', 'Domain']
    #  t << :separator
    #  t.add_row [ip_allocation.public_ip, ip_allocation.allocation_id, ip_allocation.domain]
    #end
    #logv table
    
    run_result = @ec2.run_instances({
      image_id: image_id,
      min_count: 1,
      max_count: 1,
      key_name: key[:name],
      security_group_ids: [group_id],
      instance_type: instance_type
    })
    logv "Requested instance launch. Request ID is #{run_result.reservation_id}"

    #@ec2.associate_address({
    #  instance_id: run_result.instances[0].instance_id,
    #  public_ip: ip_allocation.public_ip
    #})
    #logv "IP #{ip_allocation.public_ip} associated with instance"

    instance_public_ip = run_result.instances[0].public_ip_address
    while instance_public_ip.nil?
      logv "No public IP yet. Polling AWS..."
      sleep(10)
      dsc = @ec2.describe_instances(instance_ids: [run_result.instances[0].instance_id])
      instance_public_ip = dsc.reservations[0].instances[0].public_ip_address
    end
    
    tagCaribou(run_result.instances[0].instance_id)
    tag(run_result.instances[0].instance_id, "node_type", "master")
    
    logv "Public IP address found: #{instance_public_ip}"
    
    table = Terminal::Table.new do |t|
      t << ['Instance ID', 'Type', 'Public IP', 'State']
      t << :separator
      t.add_row [run_result.instances[0].instance_id, run_result.instances[0].instance_type, instance_public_ip, run_result.instances[0].state.name]
    end
    logv table
    
    return instance_public_ip
  end
  
  
  #
  # Shuts down the Caribou Master Node
  #
  def shutdown()
    
    nodes = findMasterNode
    if nodes.nil?
        puts "Master node not running."
        exit
    end
    begin
      response = @ec2.terminate_instances({instance_ids: [nodes[0].instance_id]})
    rescue Aws::EC2::Errors::ServiceException => e
      logv "ERROR: Failed to shut down instance #{nodes[0].instance_id}:"
      logv e.message
      exit 5
    end
    puts "instance #{nodes[0].instance_id} shutting down."
    logv "State transition: #{response.terminating_instances[0].previous_state.name} => #{response.terminating_instances[0].current_state.name}"
    
    #temporary code to just release allocated IP
    #ips = @ec2.describe_addresses()
    #puts "Elastic IPs currently allocated:"
    #puts
    #
    #table = Terminal::Table.new do |t|
    #  t << ['IP', 'Allocation ID', 'Instance ID', 'Domain']
    #  t << :separator
    #  ips.addresses.each { |ip|
    #    t.add_row [ip.public_ip, ip.allocation_id, ip.instance_id.nil? ? '-unassigned-' : ip.instance_id, ip.domain]
    #  }
    #end
    #logv table
    #
    #ips.addresses.each do |ip|
    #  if ip.domain == "vpc"
    #    @ec2.release_address({ allocation_id: ip.allocation_id })
    #  else
    #    @ec2.release_address({ public_ip: ip.public_ip })
    #  end
    #end
    #puts
    #puts "All IPs released"
  end
  
  
  #
  # Custom to_s method to include key id and region
  #
  def to_s
    return "AWS Helper with key ID #{@credentials.access_key_id} in region #{@region}"
  end


private

    #
    # Identifies all non-terminated EC2 instances that are tagged as master node in this region
    #
    def findMasterNode
      dsc =  @ec2.describe_instances(filters: [
        {name: "tag:application", values: ["caribou"]},
        {name: "tag:node_type", values: ["master"]},
        {name: "instance-state-name", values: ["pending", "running", "shutting-down", "stopping", "stopped"]}
      ])
      return nil if dsc.reservations.length == 0
      return dsc.reservations[0].instances
    end


    #
    # Creates a new Security Group which allows SSH ingress that can be used for the master node
    #
    def createSecurityGroup(name, public_ip)
      begin
        logv "Creating Caribou Default Security Group."
        result = @ec2.create_security_group({
          group_name: name,
          description: "Created from Ruby SDK"
        })
        group_id = result.data.group_id
        tagCaribou(group_id)
        group = Aws::EC2::SecurityGroup.new(group_id, {client: @ec2})
        logv "Adding SSH ingress rule for #{public_ip}"
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

    
    #
    # Tags a given resource with the caribou application tag
    #
    def tagCaribou(resource)
      tag(resource, "application", "caribou")
    end


    #
    # Tags a given resource
    #
    def tag(resource, key, value)
      @ec2.create_tags({
        resources: [ resource ],
        tags: [
           {
             key: key,
             value: value
           }
        ]
      })
    end


    #
    # Creates a new keypair and writes the private key to a file
    #
    def createKeypair(name = "caribou_keypair_#{(Time.now.to_i).to_s(16)}")
      if File.exists?("#{name}.pem")
        i = 1
        while File.exists?("#{name}_#{i}.pem")
          i += 1
        end
        name = "#{name}_#{i}.pem"
      end
      begin
        key_response =  @ec2.create_key_pair({
          key_name: name
        })
      rescue Aws::EC2::Errors::ServiceError => e
        logv e
        puts "ERROR: Failed to create keypair with name #{name}:"
        puts e.message
        return
      end
      File.open("#{name}.pem", "w") { |keyfile|
        key_response.key_material.lines { |line|
          keyfile.puts(line)
        }
      }
      puts "New key #{name} written to #{name}.pem"
      return {name: name, fingerprint: key_response.key_fingerprint }
    end


    #
    # Imports a given keyfile into EC2 and returns the name and fingerprint generated
    #
    def importKey(name, pubkey)
      puts "Importing your key as #{name}"
      begin
        import = @ec2.import_key_pair({key_name: name, public_key_material: pubkey})
        return {name: import.key_name, fingerprint: import.key_fingerprint}
      rescue Aws::EC2::Errors::ServiceError => e
        logv e
        puts "ERROR: Failed to import key:"
        puts e.message
        return
      end
    end
end