# 1. We need to require a few gems for this to work
# Rest-client gives us REST capabilities
# YAML allows ruby to understand YAML language import
# nori is being used instead of Nokogiri because it's much more lightweight and parses just enough
# awesome_print is pretty print on steroids so we can actually read the console output
require 'rest-client'
require 'yaml'
require 'nori'
require 'awesome_print'
require 'tempfile'


# 2. Load Configuration for UN & PW. This can be done in Rails using the figaro gem
# https://github.com/laserlemon/figaro
# just be careful - http://www.devfactor.net/2014/12/30/2375-amazon-mistake/
vcloud_cfg = YAML::load_file(File.join(File.dirname(File.expand_path(__FILE__)), '_config.yml'))

# 3. Set some variables. There are piped in from step 2
@username = vcloud_cfg['username']
@password = vcloud_cfg['password']
@vcd = vcloud_cfg['vcd']
@accept_param = 'application/*+xml;version=5.5'
@organization = vcloud_cfg['organization']

# 4. create a method to login to vCloud Air and save the session header
# @mysession is used in every subsequent call
# in rails we would probably need to make this persistent
def vcd_session(vcd, username, password)
  vcd_session_link = RestClient::Resource.new(vcd + '/api/sessions', username, password )
  vcd_session_response = vcd_session_link.post({'Accept' => 'application/*+xml;version=5.5'})
  myvar = 'x_vcloud_authorization'
  @mysession = vcd_session_response.headers[myvar.to_sym]
end

# setup connection and log in
vcd_session(@vcd, @username, @password)
#puts "Awsome! We're logged in. My session is " + @mysession



#=begin
# 6. XML Output of the Org vDC
# Let's explore what we need to gather from here
#puts RestClient.get(@vcd + '/api/org', :accept => @accept_param, :x_vcloud_authorization => @mysession)
#=end

=begin
# 7. Instantiate a new Nori object for parsing XML to Hash. Why? Because XML...
# Comment out 6
parser = Nori.new
puts parser.parse(RestClient.get(@vcd + '/api/org', :accept => @accept_param, :x_vcloud_authorization => @mysession))
=end

#=begin
# 8. Well that's sort of ugly, let's awesome print it
# Comment out 7
parser = Nori.new
orgList = parser.parse(RestClient.get(@vcd + '/api/org', :accept => @accept_param, :x_vcloud_authorization => @mysession))
#ap orgList
#=end

#begin
#  9. We need to start the drill down process. Using Nori as a hash we can grab the variable we need
# In pretty much every case we need a href to keep drilling
# comment out ap from 8
orgHref = orgList['OrgList']['Org']['@href']
#ap orgHref
#end


# 10. Now lets drill into the Org and see what's available there
# comment out ap from 9
orgLinks = parser.parse(RestClient.get(orgHref, :accept => @accept_param, :x_vcloud_authorization => @mysession))
#ap orgLinks



# 11. To make things easier, let's drill down once more so the array is easier to manipulate
# comment out ap from 10
orgLinkItems = orgLinks['Org']['Link']
#ap orgLinkItems



# 12. Now if we want to deploy a vApp from catalog, we need to get the individial catalogs
# to do this we will start with an empty array called catalogs because there may be more than one catalog
# from the ap above, we can see that catalogs have a certain 'type' associated with them. Lets loop through them
# all and when one is found, we will add that entries href to the array
# comment out ap from 11.
catalogs = []
orgLinkItems.each do |item|
	if item['@type'] == "application/vnd.vmware.vcloud.catalog+xml"
		catalogs << item['@href']
	end
end
#ap catalogs


# 13. Now we need to cycle through each catalog to see what it is we want
#catalogs.each do |catalog|
#	singlecat = parser.parse(RestClient.get(catalog, :accept => @accept_param, :x_vcloud_authorization => @mysession))
#	ap singlecat
#end



# 14. The above command shows we need the CatalogItems retrieved. Lets put all those into a single array called vAppTemplates
# NOTE (comment out about code now)
# comment out 13
vAppTemplates = []
catalogs.each do |catalog|
	singleCatalog = parser.parse(RestClient.get(catalog, :accept => @accept_param, :x_vcloud_authorization => @mysession))
	# create an array of items
	catalogItems = singleCatalog['Catalog']['CatalogItems']['CatalogItem']
	catalogItems.each do |catalogItem|
		# Add items to the array as a nested array
		vAppTemplates << [catalogItem['@name'], catalogItem['@href']]
	end
end

# Lets see our arrays of items
#ap vAppTemplates


=begin
# 15. Now we need to figure out which template we want to provision.  
vAppTemplates.each do |vAppTemplate|
	if vAppTemplate[0] == "CentOS63-64Bit"
		vapp = parser.parse(RestClient.get(vAppTemplate[1], :accept => @accept_param, :x_vcloud_authorization => @mysession))
		# Let's find what we need next.
		ap vapp
	end
end
=end

=begin
# 16. Digging deeper
# comment out 15
vAppTemplates.each do |vAppTemplate|
	if vAppTemplate[0] == "CentOS63-64Bit"
		vapp = parser.parse(RestClient.get(vAppTemplate[1], :accept => @accept_param, :x_vcloud_authorization => @mysession))
		# We have our HREF!! Can minimize this line if we want
		vappHref = vapp["CatalogItem"]["Entity"]["@href"]
		vappdeets = parser.parse(RestClient.get(vappHref, :accept => @accept_param, :x_vcloud_authorization => @mysession))
		# Lets look at the vApp Details
		ap vappdeets
	end
end
=end



# 17. Dig even deeper to get the network name that is needed for the XML POST
# comment out 16
vAppTemplates.each do |vAppTemplate|
	if vAppTemplate[0] == "CentOS63-64Bit"
		vapp = parser.parse(RestClient.get(vAppTemplate[1], :accept => @accept_param, :x_vcloud_authorization => @mysession))
		@vappHref = vapp["CatalogItem"]["Entity"]["@href"]
		vappdeets = parser.parse(RestClient.get(@vappHref, :accept => @accept_param, :x_vcloud_authorization => @mysession))
		@vappNetworkName = vappdeets["VAppTemplate"]["NetworkConfigSection"]["NetworkConfig"][0]["@networkName"]
	end
end



# 18. We need the network for the template.
orgLinkItems.each do |item|
	if item['@name'] == "24-194-default-routed"
		@vappNetworkHref = item['@href']
	end
end


# We need the vDC information for the template
orgLinkItems.each do |item|
	if item['@type'] == "application/vnd.vmware.vcloud.vdc+xml"
		@vdcHref = item['@href']
	end
end

# 19. Let's generate the xml needed for the post operation
File.open("xmlpost.xml", "w+") { |file| file.write(
'<?xml version="1.0" encoding="UTF-8"?>
<InstantiateVAppTemplateParams
   xmlns="http://www.vmware.com/vcloud/v1.5"
   name="LOUVMUG"
   deploy="true"
   powerOn="true"
   xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
   xmlns:ovf="http://schemas.dmtf.org/ovf/envelope/1">
   <Description>LOUVMUG Description</Description>
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

# Pull the XML file into memory
xml = File.read('xmlpost.xml')



# 20. Let's Perform a POST 
post = RestClient.post(@vdcHref + '/action/instantiateVAppTemplate', xml, :content_type => 'application/vnd.vmware.vcloud.instantiateVAppTemplateParams+xml', :accept => @accept_param, :x_vcloud_authorization => @mysession)

#We should see a 201!
ap post.code

#delete file we no longer need
File.delete(File.join(File.dirname(File.expand_path(__FILE__)), 'xmlpost.xml'))


# 5. create a method to logout of vCloud Air so sessions aren't maxed
# (cut/paste this to the end)
RestClient.delete(@vcd + '/api/session', :accept => @accept_param, :x_vcloud_authorization => @mysession)

