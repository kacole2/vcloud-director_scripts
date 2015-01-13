require 'fog'

vcloud = Fog::Compute::VcloudDirector.new(
  :vcloud_director_username => "user@org/system",
  :vcloud_director_password => "mypw",
  :vcloud_director_host => 'vcd.vchs.vmware.com',
  :vcloud_director_show_progress => true, # task progress bar on/off
)

org = vcloud.organizations.get_by_name('24-194')
catalog = org.catalogs.get_by_name('Public Catalog')
template = catalog.catalog_items.get_by_name('CentOS63-64Bit')
template.instantiate('kennyrubyfog', {
  vdc_id: org.vdcs.get_by_name('24-194').id,
  network_id: org.networks.get_by_name("24-194-default-routed").id
})