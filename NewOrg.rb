require 'rubygems'
require 'rest-client'
require 'rexml/document'
include REXML

def vcd_session(vcd, username, password)
  vcd_session_link = RestClient::Resource.new(vcd + '/api/sessions', username, password )
  vcd_session_response = vcd_session_link.post({'Accept' => 'application/*+xml;version=5.5'})
  myvar = 'x_vcloud_authorization'
  @mysession = vcd_session_response.headers[myvar.to_sym]
end

@username = 'administrator@System'
@password = 'mypassword'
@vcd = 'https://vcd-cell01.kendrickcoleman.c0m'
vcd_session(@vcd, @username, @password)

vcd_org_response = RestClient.get(@vcd + '/api/org', :accept => 'application/*+xml;version=5.5', :x_vcloud_authorization => @mysession)
puts vcd_org_response

xmlfile = File.new("new_org.xml")
vcd_new_org = RestClient.post(@vcd + '/api/admin/orgs', xmlfile, :content_type => 'application/vnd.vmware.admin.organization+xml', :accept => 'application/*+xml;version=5.5', :x_vcloud_authorization => @mysession)

puts vcd_new_org.code
puts vcd_new_org.headers
puts vcd_new_org.body