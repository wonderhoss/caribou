current_dir = File.dirname(__FILE__)
log_level                :info
log_location             STDOUT
node_name                "caribou"
client_key               "#{current_dir}/caribou.pem"
validation_client_name   "caribou-validator"
validation_key           "#{current_dir}/CARIBOU-validator.pem"
chef_server_url          "https://caribou-master/organizations/caribou"
cache_type               'BasicFile'
cache_options( :path => "#{ENV['HOME']}/.chef/checksums" )
cookbook_path            ["#{current_dir}/../cookbooks"]
