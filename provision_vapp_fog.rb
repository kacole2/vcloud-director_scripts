require 'fog'
require 'yaml'

vcloud_cfg = YAML::load_file(File.join(File.dirname(File.expand_path(__FILE__)), '_config.yml'))

vcloud = Fog::Compute::VcloudDirector.new(
  :vcloud_director_username => vcloud_cfg['username'],
  :vcloud_director_password => vcloud_cfg['password'],
  :vcloud_director_host => 'p1v17-vcd.vchs.vmware.com',
  :vcloud_director_show_progress => true, # task progress bar on/off
)

org = vcloud.organizations.get_by_name('24-194')
catalog = org.catalogs.get_by_name('Public Catalog')
template = catalog.catalog_items.get_by_name('CentOS63-64Bit')
template.instantiate('LVMUGFOG', {
  vdc_id: org.vdcs.get_by_name('24-194').id,
  network_id: org.networks.get_by_name("24-194-default-routed").id
})