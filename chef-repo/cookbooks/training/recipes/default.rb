#
# Cookbook Name:: training
# Recipe:: default
#
# Copyright (c) 2016 The Authors, All Rights Reserved.

include_recipe "tomcat::demoapp"

apt_update 'Update the apt cache daily' do
  frequency 86_400
  action :periodic
end

package 'apache2'
package 'libapache2-mod-jk'
package 'unzip'

service 'apache2' do
  supports :status => true
  action [:enable, :start]
end

template '/var/www/html/index.html' do
  source 'index.html.erb'
end

remote_file '/tmp/static.zip' do
  owner 'root'
  mode '0644'
  source 'https://s3.amazonaws.com/infra-assessment/static.zip'
end

directory '/var/www/html/companyNews' do
  owner 'root'
  mode '0755'
end

execute 'extract_static' do
  command 'unzip static.zip; cd static; cp -r styles/ images/ /var/www/html/companyNews'
  cwd '/tmp'
end

cookbook_file '/etc/apache2/sites-enabled/000-default.conf' do
  source '000-default.conf'
  owner 'root'
  group 'root'
  mode '0644'
  notifies :restart, 'service[apache2]'
end

cookbook_file '/etc/libapache2-mod-jk/httpd-jk.conf' do
  source 'httpd-jk.conf'
  owner 'root'
  group 'root'
  mode '0644'
  notifies :restart, 'service[apache2]'
end