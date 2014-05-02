require 'rubygems'
require 'rest-client'
require 'nokogiri'
require 'rexml/document'
include REXML

@username = 'administrator@System' #this requires the administrator of vCD system, not of individual Orgs
@password = 'mysecretpw'
@vcd = 'https://vcd-cell01.kendrickcoleman.c0m' #need your vcloud ip
@organization = 'internal' #this is the organization where the new org vdc will be created
@orgvdc = 'heydude' #what do you want your new organization vDC to be called?
@pvdc = 'ShuttleHosts' #what's the name of your PvDC?
@ext_networks = '50 VLAN' #only choose 1 external network at this time. haven't tested multiple yet
@storage_profile = '*' #this chooses all, or specify a specific storage profile
@network_pool = 'VCD-NI' #this can be a VXLAN network too
@vshield_edge_name = 'ruby_test' #a name for the vshield edge gateway
@vcloud_gateway = '192.168.50.220' #the address for the external side for vshield
@vcloud_gateway_netmask = '255.255.255.0'
@vcloud_ip_range_start = '192.168.50.221' #for NAT and load balancers
@vcloud_ip_range_end = '192.168.50.223' #for NAT and load balancers

def vcd_session(vcd, username, password)
  #create a api call to open a session and hold the x_cloud_authorization token
  vcd_session_link = RestClient::Resource.new(vcd + '/api/sessions', username, password )
  vcd_session_response = vcd_session_link.post({'Accept' => 'application/*+xml;version=5.5'})
  myvar = 'x_vcloud_authorization'
  @mysession = vcd_session_response.headers[myvar.to_sym]
end

def get_org(organization)
  #this will grab the Organization ID
  org_doc = Nokogiri::XML(RestClient.get(@vcd + '/api/org', :accept => 'application/*+xml;version=5.5', :x_vcloud_authorization => @mysession))
  orgs = org_doc.css('OrgList Org')
    orgs.each do |org|
        if org['name'] == organization
          @organization_id = org['href'].gsub(/.*\/org\//, "")
        end
    end
  #this will grab the Organization href from the admin login
  vcd_org_admin_doc = Nokogiri::XML(RestClient.get(@vcd + '/api/admin/org/' + @organization_id, :accept => 'application/*+xml;version=5.5', :x_vcloud_authorization => @mysession))
  admin_org = vcd_org_admin_doc.css('AdminOrg Link')
    admin_org.each do |item|
        if item['type'] == 'application/vnd.vmware.admin.createVdcParams+xml'
          @organization_admin_href = item['href']
        end
    end
end

def get_pvdc(pvdc)
  #this grabs the Provider VDC href and the ID
  pvdc_doc = Nokogiri::XML(RestClient.get(@vcd + '/api/admin', :accept => 'application/*+xml;version=5.5', :x_vcloud_authorization => @mysession))
    all_pvdcs = pvdc_doc.css('ProviderVdcReferences ProviderVdcReference')
    all_pvdcs.each do |apvdc|
          if apvdc['name'] == pvdc
            @pvdc_href = apvdc['href']
            @pvdc_id = apvdc['href'].gsub(/.*\//, "")
          end
    end
end

def get_storage_profile_and_networks(pvdc_href, storage_profile, ext_networks, network_pool)
  #grabbing storage profile href
  doc = Nokogiri::XML(RestClient.get(@pvdc_href, :accept => 'application/*+xml;version=5.5', :x_vcloud_authorization => @mysession))
    doc_storage_profile = doc.css('StorageProfiles ProviderVdcStorageProfile')
    doc_storage_profile.each do |sp|
          if sp['name'] == storage_profile
            @storage_profile_href = sp['href']#.gsub(/.*\//, "")
          end
    end
  #grabbing external network href
  doc_external_networks = doc.css('AvailableNetworks Network')
    doc_external_networks.each do |network|
          if network['name'] == ext_networks
            @external_networks_href = network['href']#.gsub(/.*\//, "")
          end
    end
    puts @external_networks_href
  #grabbing the network pool href
  doc_network_pool = doc.css('NetworkPoolReferences NetworkPoolReference')
    doc_network_pool.each do |netpool|
          if netpool['name'] == network_pool
            @network_pool_href = netpool['href']#.gsub(/.*\//, "")
          end
    end
    
end

def create_orgvdc(orgvdc, storage_profile_href, network_pool_href, pvdc, pvdc_href, organization_admin_href)
  #this is changing the xml file for the paramters we have chosen
  xmlfile = 'new_orgvdc.xml'
  xmldoc = Nokogiri::XML(File.open(xmlfile))
  namecss = xmldoc.at_css("CreateVdcParams")
  namecss['name'] = orgvdc
  storage_profilecss = xmldoc.at_css("ProviderVdcStorageProfile")
  storage_profilecss["href"] = storage_profile_href
  networkpoolcss = xmldoc.at_css("NetworkPoolReference")
  networkpoolcss['href'] = network_pool_href
  pvdc_css = xmldoc.at_css("ProviderVdcReference")
  pvdc_css["name"] = pvdc
  pvdc_css["href"] = pvdc_href
  File.open(xmlfile, 'w') {|f| f.write(xmldoc.to_xml) }
  
  #this is creating the Org VDC...finally
  xml = File.new(xmlfile)
  vcd_new_org_vdc = RestClient.post(@organization_admin_href, xml, :content_type => 'application/vnd.vmware.admin.createVdcParams+xml', :accept => 'application/*+xml;version=5.5', :x_vcloud_authorization => @mysession)
  
  #grabbing the newly created Organization VDCs href for deploying the vShield Edge
  gethttp = 'location'
  @org_vdc_http = vcd_new_org_vdc.headers[gethttp.to_sym]
  @new_org_vdc_body = vcd_new_org_vdc.body
  puts @org_vdc_http
end


def create_edge(vcd, pvdc_id, ext_networks, new_org_vdc_body, vshield_edge_name, vcloud_gateway, vcloud_gateway_netmask, vcloud_ip_range_start, vcloud_ip_range_end, organization_admin_href)  
  #this is redundant and not sure if it's necessary. but this grabs the External networks href but through the extension API call
  edge_external_network_doc = Nokogiri::XML(RestClient.get(@vcd + '/api/admin/extension/providervdc/' + pvdc_id, :accept => 'application/*+xml;version=5.5', :x_vcloud_authorization => @mysession)).remove_namespaces!
   doc_edge_external_network = edge_external_network_doc.xpath('//Network')
    doc_edge_external_network.each do |f|
          if f['name'] == ext_networks
            @edge_external_network_href = f['href']
          end
    end    
  puts @edge_external_network_href
  
  #grabs the href to deploy the vShield Edge appliance for our newly created Org VDC
  edge_doc = Nokogiri::XML(new_org_vdc_body)
    doc_vshield_edge = edge_doc.css('AdminVdc Link')
    doc_vshield_edge.each do |link|
          if link['type'] == 'application/vnd.vmware.admin.edgeGateway+xml'
            @vshield_edge_href = link['href']#.gsub(/.*\//, "")
          end
    end
  puts @vshield_edge_href
  
  #changes the XML file for our specific parameters
  xmlfile = 'new_vshield_edge.xml'
  xmldoc = Nokogiri::XML(File.open(xmlfile))
  namecss = xmldoc.at_css("EdgeGateway")
  namecss['name'] = vshield_edge_name
  network_css = xmldoc.at_css("Network")
  network_css["name"] = ext_networks
  network_css["href"] = @edge_external_network_href
  vcloud_gateway_css = xmldoc.at_css("Gateway")
  vcloud_gateway_css.content = vcloud_gateway
  vcloud_netmask_css = xmldoc.at_css("Netmask")
  vcloud_netmask_css.content = vcloud_gateway_netmask
  vcloud_ip_start_css = xmldoc.at_css("StartAddress")
  vcloud_ip_start_css.content = vcloud_ip_range_start
  vcloud_ip_end_css = xmldoc.at_css("EndAddress")
  vcloud_ip_end_css.content = vcloud_ip_range_end
  File.open(xmlfile, 'w') {|f| f.write(xmldoc.to_xml) }
  
  #this is SUPPOSED to create the new vShield Edge. But I'm getting a 400 error response code
  #error message says the vcloud ip start and end ranges are outside of the external network sub-pool. WHICH IT ISN'T! WTF!?
  #so this is where the whole script fails
  xml = File.new('new_vshield_edge.xml')
  deploy_new_edge = RestClient.post(@vshield_edge_href, xml, :content_type => 'application/vnd.vmware.admin.edgeGateway+xml', :accept => 'application/*+xml;version=5.5', :x_vcloud_authorization => @mysession)
  
  #untested.Wait 120 seconds for the Edge to be deployed
  i = 120
  begin
    puts "Creating Edge Gateway. Waiting for " + i + " seconds."
    wait 10
    i -= 10
  end while i > 0
  
  #untested. Grab the href for the vShield Gateway services for the newly created Gateway
  edge_services_doc = Nokogiri::XML(@deploy_new_edge.body)
    doc_vshield_edge_services = edge_services_doc.css('EdgeGateway Link')
    doc_vshield_edge_services.each do |link|
          if link['type'] == 'application/vnd.vmware.admin.edgeGatewayServiceConfiguration+xml'
            @vshield_edge_services_href = link['href']#.gsub(/.*\//, "")
          end
    end
  
  #untested. Change the interface href for the SNAT service
  xmlfile_services = 'new_vshield_edge_services.xml'
  xmldoc_services = Nokogiri::XML(File.open(xmlfile_services))
  interfacecss = xmldoc_services.at_css("Interface")
  namecss['href'] = @edge_external_network_href
  File.open(xmlfile_services, 'w') {|f| f.write(xmldoc_services.to_xml) }
  
  #untested. Post the new services
  xml_services = File.new(xmlfile_services)
  deploy_new_edge = RestClient.post(@vshield_edge_services_href, xml_services, :content_type => 'application/vnd.vmware.admin.edgeGatewayServiceConfiguration+xml', :accept => 'application/*+xml;version=5.5', :x_vcloud_authorization => @mysession)
end

#login and create a session token
vcd_session(@vcd, @username, @password)

#find the Orgniazation where this Org VDC will be deployed to
get_org(@organization)

#find the Provider vDC to consume resources from
get_pvdc(@pvdc)

#find the storage profile, external networks, and network pool to be used with the Org VDC
get_storage_profile_and_networks(@pcdv_href, @storage_profile, @ext_networks, @network_pool)

#lets finally create the Org VDC. This works great.
create_orgvdc(@orgvdc, @storage_profile_href, @network_pool_href, @pvdc, @pvdc_href, @organization_admin_href)

#this will create a vShield Gateway appliance for the Org VDC and create 2 default services
#first service will put an IP address on the SNAT so you can talk externally
#second service will create a default firewall rule to allow communication from internal->external but not external->!internal
#this doesnt' work yet. It keeps throwing sub-pool errors even though we are specifying IPs in the external network pool.
#hopefully someone at VMware can figure out why because I'm stumped.
create_edge(@vcd, @pvdc_id, @ext_networks, @new_org_vdc_body, @vshield_edge_name, @vcloud_gateway, @vcloud_gateway_netmask, @vcloud_ip_range_start, @vcloud_ip_range_end, @organization_admin_href)

puts "Your Organization vDC has been successfully created"
