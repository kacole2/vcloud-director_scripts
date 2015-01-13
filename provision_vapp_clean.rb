require 'rest-client'
require 'yaml'
require 'nori'
require 'awesome_print'
require 'tempfile'

vcloud_cfg = YAML::load_file(File.join(File.dirname(File.expand_path(__FILE__)), '_config.yml'))

username = vcloud_cfg['username']
password = vcloud_cfg['password']
vcd = vcloud_cfg['vcd']
accept_param = 'application/*+xml;version=5.5'
organization = vcloud_cfg['organization']

def vcd_session(vcd, username, password)
  vcd_session_link = RestClient::Resource.new(vcd + '/api/sessions', username, password )
  vcd_session_response = vcd_session_link.post({'Accept' => 'application/*+xml;version=5.5'})
  myvar = 'x_vcloud_authorization'
  @mysession = vcd_session_response.headers[myvar.to_sym]
end

def vcd_logout(vcd, accept_param, session)
  RestClient.delete(vcd + '/api/session', :accept => accept_param, :x_vcloud_authorization => session)
end

def new_vm_from_vapp(vcd, accept_param, session, requested_vApp_Template, requested_vApp_Network, requested_vApp_Name, requested_vApp_Description)
  parser = Nori.new
    orgList = parser.parse(RestClient.get(vcd + '/api/org', :accept => accept_param, :x_vcloud_authorization => session))
    orgLinks = parser.parse(RestClient.get(orgList['OrgList']['Org']['@href'], :accept => accept_param, :x_vcloud_authorization => session))
    orgLinkItems = orgLinks['Org']['Link']

    catalogs = []
    orgLinkItems.each do |item|
    	if item['@type'] == "application/vnd.vmware.vcloud.catalog+xml"
    		catalogs << item['@href']
    	end
    end

    vAppTemplates = []
    catalogs.each do |catalog|
    	singleCatalog = parser.parse(RestClient.get(catalog, :accept => accept_param, :x_vcloud_authorization => session))
    	catalogItems = singleCatalog['Catalog']['CatalogItems']['CatalogItem']
    	catalogItems.each do |catalogItem|
    		vAppTemplates << [catalogItem['@name'], catalogItem['@href']]
    	end
    end

    vAppTemplates.each do |vAppTemplate|
    	if vAppTemplate[0] == requested_vApp_Template
    		vapp = parser.parse(RestClient.get(vAppTemplate[1], :accept => accept_param, :x_vcloud_authorization => session))
    		@vappHref = vapp["CatalogItem"]["Entity"]["@href"]
    		vappdeets = parser.parse(RestClient.get(@vappHref, :accept => accept_param, :x_vcloud_authorization => session))
    		@vappNetworkName = vappdeets["VAppTemplate"]["NetworkConfigSection"]["NetworkConfig"][0]["@networkName"]
    	end
    end

    orgLinkItems.each do |item|
    	if item['@name'] == requested_vApp_Network
    		@vappNetworkHref = item['@href']
    	end
    end

    orgLinkItems.each do |item|
    	if item['@type'] == "application/vnd.vmware.vcloud.vdc+xml"
    		@vdcHref = item['@href']
    	end
    end

    File.open("xmlpost.xml", "w+") { |file| file.write(
    '<?xml version="1.0" encoding="UTF-8"?>
    <InstantiateVAppTemplateParams
       xmlns="http://www.vmware.com/vcloud/v1.5"
       name="' + requested_vApp_Name + '"
       deploy="true"
       powerOn="true"
       xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
       xmlns:ovf="http://schemas.dmtf.org/ovf/envelope/1">
       <Description>' + requested_vApp_Description + '</Description>
       <InstantiationParams>
          <NetworkConfigSection>
             <ovf:Info>Configuration parameters for logical networks
             </ovf:Info>
             <NetworkConfig
                networkName="' + @vappNetworkName + '">
                <Configuration>
                   <ParentNetwork
                      href="' + @vappNetworkHref + '" />
                   <FenceMode>bridged</FenceMode>
                </Configuration>
             </NetworkConfig>
          </NetworkConfigSection>
       </InstantiationParams>
       <Source
          href="' + @vappHref + '" />
    </InstantiateVAppTemplateParams>'
    ) }
    xml = File.read('xmlpost.xml')
    RestClient.post(@vdcHref + '/action/instantiateVAppTemplate', xml, :content_type => 'application/vnd.vmware.vcloud.instantiateVAppTemplateParams+xml', :accept => accept_param, :x_vcloud_authorization => session)
    File.delete(File.join(File.dirname(File.expand_path(__FILE__)), 'xmlpost.xml'))
end

vcd_session(vcd, username, password)
new_vm_from_vapp(vcd, accept_param, @mysession, "CentOS63-64Bit", "24-194-default-routed", "LouFinished", "Really, 1st try!")
vcd_logout(vcd, accept_param, @mysession)