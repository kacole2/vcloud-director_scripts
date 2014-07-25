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

@orgvdc = vcloud_cfg['orgvdc']
@pvdc = vcloud_cfg['pvdc']
@ext_networks = vcloud_cfg['ext_networks']
@storage_profile = vcloud_cfg['storage_profile']
@network_pool = vcloud_cfg['network_pool']
@vshield_edge_name = vcloud_cfg['vshield_edge_name']
@vcloud_gateway = vcloud_cfg['vcloud_gateway']
@vcloud_gateway_netmask = vcloud_cfg['vcloud_gateway_netmask']
@vdc_internal_network = vcloud_cfg['vdc_internal_network']
@vdc_internal_net_mask = vcloud_cfg['vdc_internal_net_mask']
@vdc_internal_gateway = vcloud_cfg['vdc_internal_gateway']
@vdc_internal_net_start = vcloud_cfg['vdc_internal_net_start']
@vdc_internal_net_end = vcloud_cfg['vdc_internal_net_end']
@accept_param = 'application/*+xml;version=5.5'

def vcd_session(vcd, username, password)
  #create a api call to open a session and hold the x_cloud_authorization token
  vcd_session_link = RestClient::Resource.new(vcd + '/api/sessions', username, password )
  vcd_session_response = vcd_session_link.post({'Accept' => @accept_param})
  myvar = 'x_vcloud_authorization'
  @mysession = vcd_session_response.headers[myvar.to_sym]
end

def get_org(organization)
  #this will grab the Organization ID
  org_doc = Nokogiri::XML(RestClient.get(@vcd + '/api/org', :accept => @accept_param, :x_vcloud_authorization => @mysession))
  orgs = org_doc.css('OrgList Org')
    orgs.each do |org|
        if org['name'] == organization
          @organization_id = org['href'].gsub(/.*\/org\//, "")
          puts "org id: " + @organization_id
        end
    end
  #this will grab the Organization href from the admin login
  vcd_org_admin_doc = Nokogiri::XML(RestClient.get(@vcd + '/api/admin/org/' + @organization_id, :accept => @accept_param, :x_vcloud_authorization => @mysession))
  admin_org = vcd_org_admin_doc.css('AdminOrg Link')
    admin_org.each do |item|
        if item['type'] == 'application/vnd.vmware.admin.createVdcParams+xml'
          @organization_admin_href = item['href']
          puts "org adm href: " + @organization_admin_href
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
            puts "pvdc href: " + @pvdc_href
            puts "pvdc id: " + @pvdc_id
          end
    end
end

def get_storage_profile_and_networks(pvdc_href, storage_profile, ext_networks, network_pool)
  #grabbing storage profile href
  doc = Nokogiri::XML(RestClient.get(@pvdc_href, :accept => 'application/*+xml;version=5.5', :x_vcloud_authorization => @mysession))
  #puts doc
    doc_storage_profile = doc.css('StorageProfiles ProviderVdcStorageProfile')
    doc_storage_profile.each do |sp|
          unless sp['name'] == storage_profile
            @storage_profile_href = sp['href']#.gsub(/.*\//, "")
            puts "storage profile: " + @storage_profile_href
          end
    end
  #grabbing external network href
  doc_external_networks = doc.css('AvailableNetworks Network')
    doc_external_networks.each do |network|
          if network['name'] == ext_networks
            @external_networks_href = network['href']#.gsub(/.*\//, "")
            puts "external network: " + @external_networks_href
          end
    end
    
  #grabbing the network pool href
  doc_network_pool = doc.css('NetworkPoolReferences NetworkPoolReference')
    doc_network_pool.each do |netpool|
          if netpool['name'] == network_pool
            @network_pool_href = netpool['href']#.gsub(/.*\//, "")
            puts "network pool: " + @network_pool_href
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
  
  #grabbing the newly created Organization VDCs href for deploying the vShield Edge later
  gethttp = 'location'
  @org_vdc_http = vcd_new_org_vdc.headers[gethttp.to_sym]
  @new_org_vdc_body = vcd_new_org_vdc.body
  puts "new VDC http: " + @org_vdc_http
  
  #grabbing the newly created Organization VDCs networks href for deploying the vDC network later
  get_vdc_net_link = Nokogiri::XML(@new_org_vdc_body)
  get_vdc_net_link_css = get_vdc_net_link.css("AdminVdc Link")
  get_vdc_net_link_css.each do |vlink|
        if vlink['type'] == 'application/vnd.vmware.vcloud.orgVdcNetwork+xml'
          @vdc_net_href = vlink['href']
          puts "vdc net href: " + @vdc_net_href
        end
  end
  
  puts "new VDC created!!!!!"
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
  puts "edge network href: " + @edge_external_network_href
  
  #grabs the href to deploy the vShield Edge appliance for our newly created Org VDC
  edge_doc = Nokogiri::XML(new_org_vdc_body)
    doc_vshield_edge = edge_doc.css('AdminVdc Link')
    doc_vshield_edge.each do |link|
          if link['type'] == 'application/vnd.vmware.admin.edgeGateway+xml'
            @vshield_edge_href = link['href']#.gsub(/.*\//, "")
          end
    end

  puts "vshield edge href: " + @vshield_edge_href
  
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
  File.open(xmlfile, 'w') {|f| f.write(xmldoc.to_xml) }
  
  xml = File.new('new_vshield_edge.xml')
  deploy_new_edge = RestClient.post(@vshield_edge_href, xml, :content_type => 'application/vnd.vmware.admin.edgeGateway+xml', :accept => 'application/*+xml;version=5.5', :x_vcloud_authorization => @mysession)
  
  #Wait 180 seconds for the Edge to be deployed
  i = 180
  begin
    puts "Creating Edge Gateway. Waiting for #{i.to_s} seconds..."
    sleep(10)
    i -= 10
  end while i > 0
  
  puts "edge created !!!"
  
  new_edge_body = deploy_new_edge.body
  edge_services_doc = Nokogiri::XML(new_edge_body)
  
  #Grab the href for the vShield edge
  doc_vshield_edge = edge_services_doc.css('EdgeGateway Link')
  doc_vshield_edge.each do |link|
        if link['type'] == 'application/vnd.vmware.admin.edgeGateway+xml'
          @org_edge_href = link['href']#.gsub(/.*\//, "")
          puts "org edge href: " + @org_edge_href
        end
  end
  
  #Grab the vShield edge IP address
  get_new_edge = RestClient.get(@org_edge_href, :accept => 'application/*+xml;version=5.5', :x_vcloud_authorization => @mysession)
  get_new_edge_body = get_new_edge.body
  get_new_edge_doc = Nokogiri::XML(get_new_edge_body)

  doc_new_edge_ip = get_new_edge_doc.css('EdgeGateway Configuration GatewayInterface SubnetParticipation IpAddress')
  doc_new_edge_ip.each do |ip|
    @edge_ip = ip.content
  end
  
  puts "retreived net edge external ip: " + @edge_ip
  
  #Update the ip sub-pool allocation on the edge
    edit_new_edge = get_new_edge_body
    edit_new_edge_doc = Nokogiri::XML(edit_new_edge)

    edit_edge_sp = edit_new_edge_doc.at_css("SubnetParticipation")

    new_edge_pool = Nokogiri::XML::Node.new "IpRanges", edit_new_edge_doc
    edit_edge_sp.add_child(new_edge_pool)

    new_edge_range = Nokogiri::XML::Node.new "IpRange", edit_new_edge_doc
      new_edge_pool.add_child(new_edge_range)

    new_edge_range_start = Nokogiri::XML::Node.new "StartAddress", edit_new_edge_doc
      new_edge_range_start.content = @edge_ip
      new_edge_range.add_child(new_edge_range_start)

    new_edge_range_end = Nokogiri::XML::Node.new "EndAddress", edit_new_edge_doc
      new_edge_range_end.content = @edge_ip
      new_edge_range.add_child(new_edge_range_end)

  edit_new_edge_xml = edit_new_edge_doc.to_xml

  update_new_edge = RestClient.put(@org_edge_href, edit_new_edge_xml, :content_type => 'application/vnd.vmware.admin.edgeGateway+xml', :accept => 'application/*+xml;version=5.5', :x_vcloud_authorization => @mysession)
  
  puts "updated edge sub-ip allocations"
  
  #Create the private network config file for this VDC
  vdcnetxmlfile = 'new_vdc_network.xml'
  vdcnetxmldoc = Nokogiri::XML(File.open(vdcnetxmlfile))
  vdcgatewaycss = vdcnetxmldoc.at_css("Gateway")
  vdcgatewaycss.content = @vdc_internal_gateway
  vdcnetmaskcss = vdcnetxmldoc.at_css("Netmask")
  vdcnetmaskcss.content = @vdc_internal_net_mask
  vdcstartaddrcss = vdcnetxmldoc.at_css("StartAddress")
  vdcstartaddrcss.content = @vdc_internal_net_start
  vdcendaddrcss = vdcnetxmldoc.at_css("EndAddress")
  vdcendaddrcss.content = @vdc_internal_net_end
  vdcedge = vdcnetxmldoc.at_css("EdgeGateway")
  vdcedge['href'] = @org_edge_href
  File.open(vdcnetxmlfile, 'w') {|f| f.write(vdcnetxmldoc.to_xml) }
  
  puts "vdc network xml creation complete"
  
  vdcnetxml = File.new(vdcnetxmlfile)
  #Deploy VDC private network is now in NewOrgVDCNetwork.rb
  
  #Grab the href for the vShield Gateway services for the newly created Gateway
    doc_vshield_edge_services = edge_services_doc.css('EdgeGateway Link')
    doc_vshield_edge_services.each do |link|
          if link['type'] == 'application/vnd.vmware.admin.edgeGatewayServiceConfiguration+xml'
            @vshield_edge_services_href = link['href']#.gsub(/.*\//, "")
            puts "vshield edge services href: " + @vshield_edge_services_href
          end
    end
  
  #Update the edge firewall services config file
  xmlfile_services = 'new_vshield_edge_services.xml'
  xmldoc_services = Nokogiri::XML(File.open(xmlfile_services))
  interfacecss = xmldoc_services.at_css("Interface")
  interfacecss['href'] = @external_networks_href
  transipcss = xmldoc_services.at_css("TranslatedIp")
  transipcss.content = @edge_ip
  origipcss = xmldoc_services.at_css("OriginalIp")
  origipcss.content = @vdc_internal_network
  srcipcss = xmldoc_services.at_css("SourceIp")
  srcipcss.content = @vdc_internal_network
  File.open(xmlfile_services, 'w') {|f| f.write(xmldoc_services.to_xml) }
  
  #Deployment of the edge services happens in the next ruby file 3NewOrgVDCNetwork.rb this just sets up the data / XML
  
  puts "new edge vdc creation completed !!!!!"
  
end

# running functions to kick-off deployment

vcd_session(@vcd, @username, @password)
get_org(@organization)
get_pvdc(@pvdc)
get_storage_profile_and_networks(@pcdv_href, @storage_profile, @ext_networks, @network_pool)
create_orgvdc(@orgvdc, @storage_profile_href, @network_pool_href, @pvdc, @pvdc_href, @organization_admin_href)
create_edge(@vcd, @pvdc_id, @ext_networks, @new_org_vdc_body, @vshield_edge_name, @vcloud_gateway, @vcloud_gateway_netmask, @vcloud_ip_range_start, @vcloud_ip_range_end, @organization_admin_href)

# deployment completed