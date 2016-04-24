#!/bin/bash

hostname caribou-master
echo "caribou-master" > /etc/hostname
IP=$(ifconfig eth0 | grep "inet addr" | cut -f 2 -d ":" | cut -f 1 -d " ")
echo "$IP caribou-master caribou-master" >> /etc/hosts
apt-get -y update
apt-get -y upgrade
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
chef-server-ctl org-create caribou 'Caribou' --association_user caribou --filename /root/chef-certs/CARIBOU-validator.pem
chef-server-ctl install chef-manage
chef-server-ctl reconfigure
chef-manage-ctl reconfigure
dpkg -i /tmp/chefdk_0.12.0-1_amd64.deb
aws s3 cp /root/chef-certs/CARIBOU-validator.pem s3://%{caribou_folder}/chef/CARIBOU-validator.pem
touch /root/cloud-init.complete