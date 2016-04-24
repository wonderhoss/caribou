#!/bin/bash

echo "%{nodename}" > /etc/hostname
IP=$(ifconfig eth0 | grep "inet addr" | cut -f 2 -d ":" | cut -f 1 -d " ")
echo "$IP %{nodename} %{nodename}" >> /etc/hosts
echo "%{master_ip} caribou-master caribou-master" >> /etc/hosts
hostname %{nodename}
apt-get update
apt-get upgrade
sudo apt-get install -y awscli curl zlib1g-dev build-essential libssl-dev libreadline-dev libyaml-dev libsqlite3-dev sqlite3 libxml2-dev libxslt1-dev libcurl4-openssl-dev python-software-properties libffi-dev
curl -sSL https://rvm.io/mpapis.asc | gpg --import -
curl -sSL https://get.rvm.io | bash -s stable --ruby
source /usr/local/rvm/scripts/rvm
/usr/local/bin/rvm install 2.3.0
/usr/local/bin/rvm use 2.3.0
rvm rubygems latest --no-ri --no-rdoc

gem install chef ohai

mkdir -p /etc/chef
(
cat << 'EOP'
{"run_list": ["role[%{role}]"]}
EOP
) > /etc/chef/first-boot.json

export AWS_ACCESS_KEY_ID=%{key}
export AWS_SECRET_ACCESS_KEY=%{secret}
export AWS_DEFAULT_REGION=%{region}
aws s3 cp s3://%{caribou_folder}/chef/CARIBOU-validator.pem /etc/chef/validation.pem

(
cat << 'EOP'
log_level :info
log_location STDOUT
chef_server_url 'https://caribou-master/organizations/caribou'
validation_client_name 'caribou-validator'
ssl_verify_mode :verify_none

EOP
) > /etc/chef/client.rb

chef-client -j /etc/chef/first-boot.json

(
cat << 'EOC'
00 *    * * *   root    . $HOME/.profile;  /usr/local/rvm/gems/ruby-2.3.0/bin/chef-client
10 *    * * *   root    . $HOME/.profile;  /usr/local/rvm/gems/ruby-2.3.0/bin/chef-client
20 *    * * *   root    . $HOME/.profile;  /usr/local/rvm/gems/ruby-2.3.0/bin/chef-client
30 *    * * *   root    . $HOME/.profile;  /usr/local/rvm/gems/ruby-2.3.0/bin/chef-client
40 *    * * *   root    . $HOME/.profile;  /usr/local/rvm/gems/ruby-2.3.0/bin/chef-client
50 *    * * *   root    . $HOME/.profile;  /usr/local/rvm/gems/ruby-2.3.0/bin/chef-client

EOC
) >> /etc/crontab
touch /root/cloud-init.complete