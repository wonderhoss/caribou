#!/bin/bash

hostname caribou-master
echo "127.0.0.1 caribou-master caribou-master" >> /etc/hosts
apt-get -y update
apt-get -y install awscli
export AWS_ACCESS_KEY_ID=%{key}
export AWS_SECRET_ACCESS_KEY=%{secret}
export AWS_DEFAULT_REGION=%{region}
export HOME=/root
aws s3 cp s3://%{caribou_folder}/vendor/chef-server-core_12.5.0-1_amd64.deb /tmp
aws s3 cp s3://%{caribou_folder}/vendor/chefdk_0.12.0-1_amd64.deb /tmp
dpkg -i /tmp/chef-server-core_12.5.0-1_amd64.deb
chef-server-ctl reconfigure
mkdir /root/chef-certs
sleep 20
chef-server-ctl user-create caribou Caribou Master %{chef_email} '%{chef_password}' --filename /root/chef-certs/caribou.pem
sudo chef-server-ctl org-create caribou 'Caribou' --association_user caribou --filename /root/chef-certs/CARIBOU-validator.pem
chef-server-ctl install chef-manage
chef-server-ctl reconfigure
chef-manage-ctl reconfigure
dpkg -i /tmp/chefdk_0.12.0-1_amd64.deb
touch /root/cloud-init.complete