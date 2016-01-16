require 'aws-sdk'

begin
  Aws.use_bundled_cert!
  credentials = Aws::Credentials.new("AKIAIFYOU7QE2MIXUV6Q", "YFp04tAetOlyYlWne3paDisuTzxH6W/5noZ2ftgx")
  ec2 = Aws::EC2::Client.new(credentials: credentials, region: 'us-east-1')

  @group_name = "Caribou Default"
  begin
    result = ec2.describe_security_groups({
      group_names: ["Caribou Default"]
    })
    @group_name = result.security_groups[0].group_name
    @group_id = result.security_groups[0].group_id
  rescue Aws::Errors::ServiceError => e
    if ! e.code == "InvalidGroupNotFound"
      puts "Error: #{e}"
    else
      puts "Caribou Default Security Group does not exist. Creating..."
      result = ec2.create_security_group({
        dry_run: false,
        group_name: "Caribou Default",
        description: "Created from Ruby SDK"
      })
      @group_id = result.data.group_id
      ec2.create_tags({
        resources: [ @group_id ],
        tags: [
          {
            key: "application",
            value: "caribou"
          }
        ]
      })
      puts "New group #{@group_name} created with id #{@group_id}\nGroup tagged with \"application:caribou\"."
    end
  end

  puts "Security Group #{@group_name} has ID #{@group_id}"

rescue Aws::Errors::ServiceError => e
  puts "Error: #{e}"
  puts e.code
  puts e.context
end