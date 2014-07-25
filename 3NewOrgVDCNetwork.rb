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
          @organization_href = org['href']
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

def create_orgvdcnet(orgvdc, organization_href, organization_admin_href)
  
  #getting org vdc networks link
  get_new_org_admin = RestClient.get(@organization_href, :accept => 'application/*+xml;version=5.5', :x_vcloud_authorization => @mysession)
  get_new_org_admin_body = get_new_org_admin.body
  get_vdc_link = Nokogiri::XML(get_new_org_admin_body)
  get_vdc_link_css = get_vdc_link.css("Org Link")
  get_vdc_link_css.each do |link|
        if link['type'] == 'application/vnd.vmware.vcloud.vdc+xml'
          @vdc_href = link['href']
          puts "vdc href: " + @vdc_href
        end
  end
  
  #getting org vdc networks link
  get_vdc_data = RestClient.get(@vdc_href, :accept => 'application/*+xml;version=5.5', :x_vcloud_authorization => @mysession)
  get_vdc_data_body = get_vdc_data.body
  get_vdc_net_link = Nokogiri::XML(get_vdc_data_body)
  get_vdc_net_link_css = get_vdc_net_link.css("Vdc Link")
  get_vdc_net_link_css.each do |vlink|
        if vlink['type'] == 'application/vnd.vmware.vcloud.orgVdcNetwork+xml'
          @vdc_net_href = vlink['href']
          puts "vdc net href: " + @vdc_net_href
        end
  end

  puts "creating net vdc private network"
  
  vdcnetxmlfile = 'new_vdc_network.xml'
  vdcnetxml = File.new(vdcnetxmlfile)
  

  begin
    RestClient.post(@vdc_net_href, vdcnetxml, :content_type => 'application/vnd.vmware.vcloud.orgVdcNetwork+xml', :accept => 'application/*+xml;version=5.5', :x_vcloud_authorization => @mysession) { |response, request, result, &block|
    puts "vcd network creation http response code: " + response.code.to_s
    case response.code
      when 201
        puts "vdc network creation completed!!!"
      else
        puts "!!!### vdc network creation FAILED - vcloud is probably busy, just re-run this script a few times until it completes"
        abort("!!!### the vCloud API was not ready, please try again")
      end
    }
  end

  
  #Wait 60 seconds for the vdc net to be spun up
  i = 60
  begin
    puts "Initializing VDC Network. Waiting for #{i.to_s} seconds..."
    sleep(10)
    i -= 10
  end while i > 0

  
end

def create_edge_services(orgvdc, organization_href, organization_admin_href)
  
  #getting org edge query link
  get_vdc_q_data = RestClient.get(@vdc_href, :accept => 'application/*+xml;version=5.5', :x_vcloud_authorization => @mysession)
  get_vdc_q_data_body = get_vdc_q_data.body
  get_edge_q_link = Nokogiri::XML(get_vdc_q_data_body)
  get_edge_q_link_css = get_edge_q_link.css("Vdc Link")
  get_edge_q_link_css.each do |qlink|
        if qlink['rel'] == 'edgeGateways' and qlink['type'] == 'application/vnd.vmware.vcloud.query.records+xml'
          @vdc_edge_q_href = qlink['href']
          puts "vdc edge query href: " + @vdc_edge_q_href
        end
  end
  
  get_edges = RestClient.get(@vdc_edge_q_href, :accept => 'application/*+xml;version=5.5', :x_vcloud_authorization => @mysession)
  get_edges_link = Nokogiri::XML(get_edges)
  get_edges_link_css = get_edges_link.css("QueryResultRecords EdgeGatewayRecord")
  get_edges_link_css.each do |edges|
    @vdc_edge_href = edges['href']
      puts "vdc net href: " + @vdc_edge_href
    end

    get_edge = RestClient.get(@vdc_edge_href, :accept => 'application/*+xml;version=5.5', :x_vcloud_authorization => @mysession)
    get_edge_s_link = Nokogiri::XML(get_edge)
    get_edge_s_link_css = get_edge_s_link.css("EdgeGateway Link")
    get_edge_s_link_css.each do |slink|
      if slink['type'] == 'application/vnd.vmware.admin.edgeGatewayServiceConfiguration+xml'
        @vdc_edge_s_href = slink['href']
        puts "vdc edge services href: " + @vdc_edge_s_href
      end
    end
    
    #ok finally, we can setup some services
    
    puts "creating edge nat and firewall rules"
    
    xmlfile_services = 'new_vshield_edge_services.xml'
    xml_services = File.new(xmlfile_services)
    create_edge_services = RestClient.post(@vdc_edge_s_href, xml_services, :content_type => 'application/vnd.vmware.admin.edgeGatewayServiceConfiguration+xml', :accept => 'application/*+xml;version=5.5', :x_vcloud_authorization => @mysession)

    puts "created edge nat and firewall rules!!!"

end

# running functions to kick-off deployment

vcd_session(@vcd, @username, @password)
get_org(@organization)

create_orgvdcnet(@orgvdc, @organization_href, @organization_admin_href)
create_edge_services(@orgvdc, @organization_href, @organization_admin_href)

puts "vdc network configuration complete!!!"

# deployment completed



