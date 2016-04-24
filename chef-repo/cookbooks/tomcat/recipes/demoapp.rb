# make sure we have java installed
include_recipe 'java'

# Install Tomcat 8.0.32 to the default location
tomcat_install 'demoapp' do
  version '8.0.32'
end

# Drop off our own server.xml that uses a non-default port setup
cookbook_file '/opt/tomcat_demoapp/conf/server.xml' do
  source 'demoapp_server.xml'
  owner 'root'
  group 'root'
  mode '0644'
  notifies :restart, 'tomcat_service[demoapp]'
end

dirs = ['Users', 'dcameron', 'persistence', 'files']
path = ''
dirs.each do |dir|
  path = File.join(path, dir)
  directory path do
    owner 'tomcat_demoapp'
    group 'tomcat_demoapp'
    mode '0777'
  end
end

remote_file '/opt/tomcat_demoapp/webapps/sample.war' do
  owner 'tomcat_demoapp'
  mode '0644'
  source 'https://tomcat.apache.org/tomcat-6.0-doc/appdev/sample/sample.war'
  checksum '89b33caa5bf4cfd235f060c396cb1a5acb2734a1366db325676f48c5f5ed92e5'
end

remote_file '/opt/tomcat_demoapp/webapps/companyNews.war' do
  owner 'tomcat_demoapp'
  mode '0644'
  source 'https://s3.amazonaws.com/infra-assessment/companyNews.war'
end

# start the helloworld tomcat service using a non-standard pic location
tomcat_service 'demoapp' do
  action [:start, :enable]
  env_vars [{ 'CATALINA_PID' => '/opt/tomcat_demoapp/bin/non_standard_location.pid' }]
end