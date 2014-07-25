require 'rest-client'
require 'nokogiri'
require 'rexml/document'
include REXML
require 'yaml'

# load configuration

vcloud_cfg = YAML::load_file(File.join(File.dirname(File.expand_path(__FILE__)), '_config.yml'))

# pull in config data and init variables

@username = vcloud_cfg['username']
@password = vcloud_cfg['password']

@vcd = vcloud_cfg['vcd']

@organization = vcloud_cfg['organization']

def vcd_session(vcd, username, password)
  vcd_session_link = RestClient::Resource.new(vcd + '/api/sessions', username, password )
  vcd_session_response = vcd_session_link.post({'Accept' => 'application/*+xml;version=5.5'})
  myvar = 'x_vcloud_authorization'
  @mysession = vcd_session_response.headers[myvar.to_sym]
end

# set org name in XML file

orgxmlfile = 'new_org.xml'
orgxmldoc = Nokogiri::XML(File.open(orgxmlfile))
orgnamecss = orgxmldoc.at_css("AdminOrg")
orgnamecss['name'] = @organization
File.open(orgxmlfile, 'w') {|f| f.write(orgxmldoc.to_xml) }

# setup connection and log in

vcd_session(@vcd, @username, @password)
vcd_org_response = RestClient.get(@vcd + '/api/org', :accept => 'application/*+xml;version=5.5', :x_vcloud_authorization => @mysession)

# post org creation xml data

puts "starting org creation"

vcdnewxmlfile = File.new(orgxmlfile)
vcd_new_org = RestClient.post(@vcd + '/api/admin/orgs', vcdnewxmlfile, :content_type => 'application/vnd.vmware.admin.organization+xml', :accept => 'application/*+xml;version=5.5', :x_vcloud_authorization => @mysession)

puts "new organisation created!!!"

# org setup completed