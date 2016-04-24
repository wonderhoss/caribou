require 'aws-sdk'
require_relative 'verbose.rb'
require_relative 'chef_provision_helper.rb'
require_relative 'env_parser.rb'
require 'netaddr'
require 'open-uri'
require 'terminal-table'
require 'base64'

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
    @basedir = options[:basedir]
    
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
    @chef_helper = ChefHelper.new(options)
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
  def getSecurityGroupId(name = SECURITY_GROUP_DEFAULT, vpc_id)
    public_ip = open('http://whatismyip.akamai.com').read
    public_ip << "/32"
    ssh_in_allowed = false
    begin
      result = @ec2.describe_security_groups({
        filters: [
          {name: "group-name", values: [name]},
          {name: "vpc-id", values: [vpc_id]}
        ]
      })
      return createSecurityGroup(name, public_ip, vpc_id) if result.security_groups.length == 0
      group_id = result.security_groups[0].group_id
      group = Aws::EC2::SecurityGroup.new(group_id, {client: @ec2})
      logv "Existing group found\n"
      logv "Public IP queried from Akamai: #{public_ip}\n\n"
      logv "Ingress Permissions on existing group:\n"
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
        return createSecurityGroup(name, public_ip, vpc_id)
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
  
  
  def deployEnvironment(environment_name)
    env_filename = "#{@basedir}/environments/#{environment_name}.json"
    if !File.readable?(env_filename)
        puts "Environment description #{env_filename} does not exist."
        exit 2
    end
    begin
      environment = EnvironmentParser::parseEnv(File.read(env_filename))
    rescue EnvironmentParser::EnvironmentParseError => e
      puts "Failed to parse environment description #{env_filename}: #{e}"
      exit 2
    end
    master = findMasterNode
    if master.nil?
      puts "Master node does not seem to be up. Cannot deploy Environment."
      exit 5
    end
    master = master[0]
    master_ip = master.network_interfaces[0].private_ip_address
    #TODO: Get keyname from environment file to allow for separate keys for each swarm
    #TODO: Assumes that master will only ever have one group. Better way to identify group required. Maybe from env again.
    security_group_id = master.security_groups[0].group_id
    environment[:swarms].each do |swarm|
      logv "Deploying Swarm #{swarm[:name]}:"
      logv swarm
      if swarm[:lb]
        #TODO: Set up load balancer
      end
      if swarm[:asg]
        #TODO: Set up auto-scaling group and run configuration
      else
        swarm[:instance_count].times do |i|
          init_script = @chef_helper.get_node_cloudinit_script(master_ip, "caribou-#{swarm[:name]}-#{i}", swarm[:role])
          run_result = @ec2.run_instances({
            image_id: swarm[:ami],
            min_count: 1,
            max_count: 1,
            subnet_id: master.subnet_id,
            key_name: master.key_name,
            security_group_ids: [security_group_id],
            instance_type: swarm[:instance_type],
            user_data: Base64.encode64(init_script)
          })
          tagCaribou(run_result.instances[0].instance_id)
          tag(run_result.instances[0].instance_id, "node_type", "swarm-node")
          tag(run_result.instances[0].instance_id, "Name", "caribou-#{swarm[:name]}-#{i}")
          tag(run_result.instances[0].instance_id, "environment", environment_name)
          tag(run_result.instances[0].instance_id, "swarm", swarm[:name])
          logv "Requested instance launch for caribou-#{swarm[:name]}-#{i}. Request ID is #{run_result.reservation_id}"
        end
      end
      puts "Done with Environment #{environment_name}"
    end
  end

  
  
  #
  # Deploys a new EC2 instance to use as master node
  #
  def deployMaster(security_group, keyname = nil, instance_type = "t1.micro", image_id = "ami-7b386c11", pubkey = nil)
    nodes = findMasterNode
    if !nodes.nil?
        puts "A Caribou master node is already running:"
        puts masterStatus
        exit 5
    end
    
    if keyname.nil?
      if pubkey.nil?
        if @newkey
          puts "Creating new key pair..."
          key = createKeypair
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
    
    vpc_config = findVPC()
    group_id = getSecurityGroupId(security_group, vpc_config[:vpc_id])
    #TODO: Check that security group belongs to same subnet
   
    #ip_allocation = @ec2.allocate_address()
    #logv "Allocated IP address:"
    #table = Terminal::Table.new do |t|
    #  t << ['IP', 'Allocation ID', 'Domain']
    #  t << :separator
    #  t.add_row [ip_allocation.public_ip, ip_allocation.allocation_id, ip_allocation.domain]
    #end
    #logv table
    
    if @chef_helper.find_file("vendor", "chef-server-core_12.5.0-1_amd64.deb")
      logv "Chef Server installer package already found on S3"
    else
      @chef_helper.upload_file("vendor", "#{@basedir}/vendor/chef-server-core_12.5.0-1_amd64.deb")
    end
    if @chef_helper.find_file("vendor", "chefdk_0.12.0-1_amd64.deb")
      logv "Chef Server installer package already found on S3"
    else
      @chef_helper.upload_file("vendor", "#{@basedir}/vendor/chefdk_0.12.0-1_amd64.deb")
    end
    
    begin
      run_result = @ec2.run_instances({
        image_id: image_id,
        min_count: 1,
        max_count: 1,
        private_ip_address: "172.16.0.10",
        subnet_id: vpc_config[:subnet_id],
        key_name: key[:name],
        security_group_ids: [group_id],
        instance_type: instance_type,
        user_data: Base64.encode64(@chef_helper.get_master_cloudinit_script)
      })
      logv "Requested instance launch. Request ID is #{run_result.reservation_id}"
    rescue Aws::EC2::Errors::InvalidIPAddressInUse
      #TODO: Better check for master node already running
      puts "Another node is already deployed with master ip 172.16.0.10."
      return nil
    end
    #@ec2.associate_address({
    #  instance_id: run_result.instances[0].instance_id,
    #  public_ip: ip_allocation.public_ip
    #})
    #logv "IP #{ip_allocation.public_ip} associated with instance"


    instance_public_ip = run_result.instances[0].public_ip_address
    while instance_public_ip.nil?
      logv "Waiting for instance public IP to be assigned..."
      sleep(5)
      dsc = @ec2.describe_instances(instance_ids: [run_result.instances[0].instance_id])
      instance_public_ip = dsc.reservations[0].instances[0].public_ip_address
    end
    
    tagCaribou(run_result.instances[0].instance_id)
    tag(run_result.instances[0].instance_id, "node_type", "master")
    tag(run_result.instances[0].instance_id, "Name", "caribou-master")
    
    logv "Public IP address found: #{instance_public_ip}"
    puts "Waiting for cloud-init to finish bootstrapping Chef server. This will some time."
    sleep 60
    
    #TODO: Display rolling update of instance's cloud-init-output if verbose logging enabled
    
    while (!@chef_helper.cloud_init_complete?(instance_public_ip, key[:name]))
        print "."
        sleep 20
    end
    print "\n"
    puts
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


#private

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

private

    #
    # Identifies the primary subnet within the VPC used to deploy hosts
    #
    def findSubnet
        dsc = @ec2.describe_subnets({filters: [
          {name:"tag:application", values: ["caribou"]}
        ]})
        return nil if dsc.subnets.length == 0
        return dsc.subnets[0]
    end
    

    #
    # Identifies the Caribou default VPC
    #
    def findVPC
      #TODO: Check for existing VPC with Caribou tag and setup_complete
      dsc = @ec2.describe_vpcs({filters: [
        {name: "tag:application", values: ["caribou"]}
      ]})
      if dsc.vpcs.length == 0
        return createVPC("172.16.0.0/24")
      else
        vpc_id = dsc.vpcs[0].vpc_id
        dsc = @ec2.describe_tags({filters: [
          {name: "resource-id", values: [vpc_id]},
          {name: "key", values: ["setup_complete"]}
        ]})
        if dsc.tags.length == 0
          puts "Unfinished VPC found. Please clean up manually before retrying."
          exit 5
          #TODO: Unfinished VPC found. Tear down and restart
        else
          logv "Retrieving details for existing VPC #{vpc_id}."
          dsc = @ec2.describe_internet_gateways({filters: [
            {name: "attachment.vpc-id", values: [vpc_id]}
          ]})
          #TODO: If setup is complete, IG should exist, but better to check before doing this
          ig_id = dsc.internet_gateways[0].internet_gateway_id
          
          dsc = @ec2.describe_subnets({filters: [
            {name: "vpc-id", values: [vpc_id]}
          ]})
          #TODO: There may well be more subnets than just one, so find the right one here
          subnet_id = dsc.subnets[0].subnet_id
          
          dsc = @ec2.describe_route_tables({filters: [
            {name: "association.subnet-id", values: [subnet_id]}
          ]})
          #TODO: If setup is complete, the routing table should exist, but better to check before doing this
          rt_id = dsc.route_tables[0].route_table_id
          return {vpc_id: vpc_id, ig_id: ig_id, rt_id: rt_id, subnet_id: subnet_id}
        end
      end

    end
    
    
    #
    # Creates a new Security Group which allows SSH ingress that can be used for the master node
    #
    def createSecurityGroup(name, public_ip, vpc_id)
      begin
        if vpc_id != nil
          logv "Creating Caribou Default Security Group for VPC #{vpc_id}."
            result = @ec2.create_security_group({
            group_name: name,
            description: "Created from Ruby SDK",
            vpc_id: vpc_id
          })
        else
          logv "Creating Caribou Default Security Group."
          result = @ec2.create_security_group({
            group_name: name,
            description: "Created from Ruby SDK"
          })
        end
        group_id = result.data.group_id
        #TODO: Wait for security group to be created properly
        sleep 5
        logv "Security Group #{group_id} created."
        tagCaribou(group_id)
        group = Aws::EC2::SecurityGroup.new(group_id, {client: @ec2})
        logv "Adding SSH ingress rule for #{public_ip}"
        group.authorize_ingress({
          cidr_ip: public_ip,
          from_port: 22,
          to_port: 22,
          ip_protocol: "tcp"
        })
        logv "Adding HTTPS ingress rule for #{public_ip}"
        group.authorize_ingress({
          cidr_ip: public_ip,
          from_port: 443,
          to_port: 443,
          ip_protocol: "tcp"
        })
        logv "Adding port 8443 ingress rule for #{public_ip}"
        group.authorize_ingress({
          cidr_ip: public_ip,
          from_port: 8443,
          to_port: 8443,
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
  # Create VPC, Internet Gateway and Routing Table
  #
  def createVPC(block)
    #TODO: Check for existing VPC first
    puts "Creating and configuring Caribou VPC"
    run_result = @ec2.create_vpc({cidr_block: block})
    logv " -> VPC created"
    vpc_id = run_result.vpc.vpc_id
    loop do
      begin
        dsc = @ec2.describe_vpcs({vpc_ids: [vpc_id]})
      rescue Aws::EC2::Errors::InvalidVpcIdNotFound
        logv "Waiting for VPC ID (#{vpc_id}) to be recognized..."
        sleep(5)       
      end
      state = dsc.vpcs[0].state
      break if state == "available"
      logv "Waiting for VPC (#{state}) to become available..."
      sleep(5)
    end
    tagCaribou(vpc_id)
    table = Terminal::Table.new do |t|
      t << ['VPC ID', 'State', 'CIDR Block', 'Instance Tenancy']
      t << :separator
      t.add_row [run_result.vpc.vpc_id, run_result.vpc.state, run_result.vpc.cidr_block, run_result.vpc.instance_tenancy]
    end
    logv table
    run_result = @ec2.create_subnet({vpc_id: vpc_id, cidr_block: block})
    subnet_id = run_result.subnet.subnet_id
    tagCaribou(subnet_id)
    run_result = @ec2.modify_subnet_attribute({subnet_id: subnet_id, map_public_ip_on_launch: { value: true }})
    logv " -> Subnet created"
    
    #TODO: Check for existing gateway first
    run_result = @ec2.create_internet_gateway()
    ig_id = run_result.internet_gateway.internet_gateway_id
    tagCaribou(ig_id)
    logv " -> Internet Gateway created"
    run_result = @ec2.attach_internet_gateway({internet_gateway_id: ig_id, vpc_id: vpc_id})
    logv " -> Internet Gateway attached to VPC"
    
    #TODO: Check for existing routing table first
    run_result = @ec2.create_route_table({vpc_id: vpc_id})
    rt_id = run_result.route_table.route_table_id
    tagCaribou(rt_id)
    logv " -> Routing Table created"
    run_result = @ec2.create_route({route_table_id: rt_id, gateway_id: ig_id, destination_cidr_block: "0.0.0.0/0"})
    logv " -> Internet Gateway Route added"
    
    run_result = @ec2.describe_route_tables({route_table_ids: [rt_id]})
    table = Terminal::Table.new do |t|
      t << ['Destination', 'State', 'Origin']
      t << :separator
      run_result.route_tables[0].routes.each do |route|
        t.add_row [route.destination_cidr_block, route.state, route.origin]
      end
    end
    logv table
    
    run_result = @ec2.associate_route_table({
      subnet_id: subnet_id,
      route_table_id: rt_id
    })
    logv "Routing Table #{rt_id} associated with Subnet #{subnet_id}"
    
    tag(vpc_id, "setup_complete", "true")
    return {vpc_id: vpc_id, ig_id: ig_id, rt_id: rt_id, subnet_id: subnet_id}
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