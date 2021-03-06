notice('MODULAR: openstack-controller.pp')

$nova_rate_limits               = hiera('nova_rate_limits')
$primary_controller             = hiera('primary_controller')
$use_neutron                    = hiera('use_neutron', false)
$cinder_rate_limits             = hiera('cinder_rate_limits')
$nova_report_interval           = hiera('nova_report_interval')
$nova_service_down_time         = hiera('nova_service_down_time')
$use_syslog                     = hiera('use_syslog', true)
$syslog_log_facility_glance     = hiera('syslog_log_facility_glance', 'LOG_LOCAL2')
$syslog_log_facility_cinder     = hiera('syslog_log_facility_cinder', 'LOG_LOCAL3')
$syslog_log_facility_neutron    = hiera('syslog_log_facility_neutron', 'LOG_LOCAL4')
$syslog_log_facility_nova       = hiera('syslog_log_facility_nova','LOG_LOCAL6')
$syslog_log_facility_keystone   = hiera('syslog_log_facility_keystone', 'LOG_LOCAL7')
$syslog_log_facility_ceilometer = hiera('syslog_log_facility_ceilometer','LOG_LOCAL0')
$management_vip                 = hiera('management_vip')
$public_vip                     = hiera('public_vip')
$storage_address                = hiera('storage_address')
$sahara_hash                    = hiera_hash('sahara', {})
$cinder_hash                    = hiera_hash('cinder', {})
$nodes_hash                     = hiera('nodes', {})
$mysql_hash                     = hiera_hash('mysql', {})
$controllers                    = hiera('controllers')
$access_hash                    = hiera_hash('access', {})
$keystone_hash                  = hiera_hash('keystone', {})
$glance_hash                    = hiera_hash('glance', {})
$storage_hash                   = hiera_hash('storage', {})
$nova_hash                      = hiera_hash('nova', {})
$internal_address               = hiera('internal_address')
$rabbit_hash                    = hiera_hash('rabbit_hash', {})
$ceilometer_hash                = hiera_hash('ceilometer',{})
$mongo_hash                     = hiera_hash('mongo', {})
$syslog_log_facility_ceph       = hiera('syslog_log_facility_ceph','LOG_LOCAL0')
$workloads_hash                 = hiera_hash('workloads_collector', {})
$service_endpoint               = hiera('service_endpoint', $management_vip)
$db_host                        = pick($nova_hash['db_host'], $management_vip)
$nova_db_user                   = pick($nova_hash['db_user'], 'nova')
$keystone_user                  = pick($nova_hash['user'], 'nova')
$keystone_tenant                = pick($nova_hash['tenant'], 'services')
$glance_api_servers             = hiera('glance_api_servers', "$management_vip:9292")
$region                         = hiera('region', 'RegionOne')

$controller_internal_addresses  = nodes_to_hash($controllers,'name','internal_address')
$controller_nodes               = ipsort(values($controller_internal_addresses))
$controller_hostnames           = keys($controller_internal_addresses)
$cinder_iscsi_bind_addr         = $storage_address
$roles                          = node_roles($nodes_hash, hiera('uid'))

$floating_hash = {}

class { 'l23network' :
  use_ovs => $use_neutron
}

if $use_neutron {
  $network_provider          = 'neutron'
  $novanetwork_params        = {}
  $neutron_config            = hiera_hash('quantum_settings')
  $neutron_db_password       = $neutron_config['database']['passwd']
  $neutron_user_password     = $neutron_config['keystone']['admin_password']
  $neutron_metadata_proxy_secret = $neutron_config['metadata']['metadata_proxy_shared_secret']
  $base_mac                  = $neutron_config['L2']['base_mac']
} else {
  $network_provider   = 'nova'
  $floating_ips_range = hiera('floating_network_range')
  $neutron_config     = {}
  $novanetwork_params = hiera('novanetwork_parameters')
}

if hiera('amqp_nodes', false) {
  $amqp_nodes = hiera('amqp_nodes')
}
elsif $internal_address in $controller_nodes {
  # prefer local MQ broker if it exists on this node
  $amqp_nodes = concat(['127.0.0.1'], fqdn_rotate(delete($controller_nodes, $internal_address)))
} else {
  $amqp_nodes = fqdn_rotate($controller_nodes)
}
$amqp_port = hiera('amqp_port', '5673')
$amqp_hosts = inline_template("<%= @amqp_nodes.map {|x| x + ':' + @amqp_port}.join ',' %>")

# RabbitMQ server configuration
$rabbitmq_bind_ip_address = 'UNSET'              # bind RabbitMQ to 0.0.0.0
$rabbitmq_bind_port = $amqp_port
$rabbitmq_cluster_nodes = $controller_hostnames  # has to be hostnames

if ($storage_hash['images_ceph']) {
  $glance_backend = 'ceph'
  $glance_known_stores = [ 'glance.store.rbd.Store', 'glance.store.http.Store' ]
} elsif ($storage_hash['images_vcenter']) {
  $glance_backend = 'vmware'
  $glance_known_stores = [ 'glance.store.vmware_datastore.Store', 'glance.store.http.Store' ]
} else {
  $glance_backend = 'swift'
  $glance_known_stores = [ 'glance.store.swift.Store', 'glance.store.http.Store' ]
}

# Determine who should get the volume service

if (member($roles, 'cinder') and $storage_hash['volumes_lvm']) {
  $manage_volumes = 'iscsi'
} elsif (member($roles, 'cinder') and $storage_hash['volumes_vmdk']) {
  $manage_volumes = 'vmdk'
} elsif ($storage_hash['volumes_ceph']) {
  $manage_volumes = 'ceph'
} else {
  $manage_volumes = false
}

if !$ceilometer_hash {
  $ceilometer_hash = {
    enabled         => false,
    db_password     => 'ceilometer',
    user_password   => 'ceilometer',
    metering_secret => 'ceilometer',
  }
  $ext_mongo = false
} else {
  # External mongo integration
  if $mongo_hash['enabled'] {
    $ext_mongo_hash         = hiera('external_mongo')
    $ceilometer_db_user     = $ext_mongo_hash['mongo_user']
    $ceilometer_db_password = $ext_mongo_hash['mongo_password']
    $ceilometer_db_name     = $ext_mongo_hash['mongo_db_name']
    $ext_mongo              = true
  } else {
    $ceilometer_db_user     = 'ceilometer'
    $ceilometer_db_password = $ceilometer_hash['db_password']
    $ceilometer_db_name     = 'ceilometer'
    $ext_mongo              = false
    $ext_mongo_hash         = {}
  }
}

if $ext_mongo {
  $mongo_hosts = $ext_mongo_hash['hosts_ip']
  if $ext_mongo_hash['mongo_replset'] {
    $mongo_replicaset = $ext_mongo_hash['mongo_replset']
  } else {
    $mongo_replicaset = undef
  }
} elsif $ceilometer_hash['enabled'] {
  $mongo_hosts = mongo_hosts($nodes_hash)
  if size(mongo_hosts($nodes_hash, 'array', 'mongo')) > 1 {
    $mongo_replicaset = 'ceilometer'
  } else {
    $mongo_replicaset = undef
  }
}

# SQLAlchemy backend configuration
$max_pool_size = min($::processorcount * 5 + 0, 30 + 0)
$max_overflow = min($::processorcount * 5 + 0, 60 + 0)
$max_retries = '-1'
$idle_timeout = '3600'

# TODO: openstack_version is confusing, there's such string var in hiera and hardcoded hash
$hiera_openstack_version = hiera('openstack_version')
$openstack_version = {
  'keystone'   => 'installed',
  'glance'     => 'installed',
  'horizon'    => 'installed',
  'nova'       => 'installed',
  'novncproxy' => 'installed',
  'cinder'     => 'installed',
}

#################################################################
if hiera('use_vcenter', false) or hiera('libvirt_type') == 'vcenter' {
  $multi_host = false
} else {
  $multi_host = true
}

class { '::openstack::controller':
  private_interface              => $use_neutron ? { true=>false, default=>hiera('private_int')},
  public_interface               => hiera('public_int', undef),
  public_address                 => $public_vip,    # It is feature for HA mode.
  internal_address               => $management_vip,  # All internal traffic goes
  admin_address                  => $management_vip,  # through load balancer.
  floating_range                 => $use_neutron ? { true =>$floating_hash, default  =>false},
  fixed_range                    => $use_neutron ? { true =>false, default =>hiera('fixed_network_range')},
  multi_host                     => $multi_host,
  network_config                 => hiera('network_config', {}),
  num_networks                   => hiera('num_networks', undef),
  network_size                   => hiera('network_size', undef),
  network_manager                => hiera('network_manager', undef),
  network_provider               => $network_provider,
  verbose                        => true,
  debug                          => hiera('debug', true),
  auto_assign_floating_ip        => hiera('auto_assign_floating_ip', false),
  glance_api_servers             => $glance_api_servers,
  primary_controller             => $primary_controller,
  novnc_address                  => $internal_address,
  nova_db_user                   => $nova_db_user,
  nova_db_password               => $nova_hash[db_password],
  nova_user                      => $keystone_user,
  nova_user_password             => $nova_hash[user_password],
  nova_user_tenant               => $keystone_tenant,
  queue_provider                 => 'rabbitmq',
  amqp_hosts                     => $amqp_hosts,
  amqp_user                      => $rabbit_hash['user'],
  amqp_password                  => $rabbit_hash['password'],
  rabbit_ha_queues               => true,
  cache_server_ip                => $controller_nodes,
  api_bind_address               => $internal_address,
  db_host                        => $db_host,
  service_endpoint               => $service_endpoint,
  neutron_metadata_proxy_secret  => $neutron_metadata_proxy_secret,
  cinder                         => true,
  ceilometer                     => $ceilometer_hash[enabled],
  use_syslog                     => $use_syslog,
  syslog_log_facility_nova       => $syslog_log_facility_nova,
  nova_rate_limits               => $nova_rate_limits,
  nova_report_interval           => $nova_report_interval,
  nova_service_down_time         => $nova_service_down_time,
  ha_mode                        => true,
  # SQLALchemy backend
  max_retries                    => $max_retries,
  max_pool_size                  => $max_pool_size,
  max_overflow                   => $max_overflow,
  idle_timeout                   => $idle_timeout,
}

package { 'socat': ensure => present }

#TODO: PUT this configuration stanza into nova class
nova_config { 'DEFAULT/use_cow_images':                   value => hiera('use_cow_images')}

if $primary_controller {

  $haproxy_stats_url = "http://${management_vip}:10000/;csv"

  haproxy_backend_status { 'nova-api' :
    name    => 'nova-api-2',
    url     => $haproxy_stats_url,
  }

  Openstack::Ha::Haproxy_service <| |> -> Haproxy_backend_status <| |>

  Class['nova::api'] -> Haproxy_backend_status['nova-api']

  exec { 'create-m1.micro-flavor' :
    path    => '/sbin:/usr/sbin:/bin:/usr/bin',
    environment => [
      "OS_TENANT_NAME=${keystone_tenant}",
      "OS_USERNAME=${keystone_user}",
      "OS_PASSWORD=${nova_hash['user_password']}",
      "OS_AUTH_URL=http://${service_endpoint}:5000/v2.0/",
      'OS_ENDPOINT_TYPE=internalURL',
      "OS_REGION_NAME=${region}",
    ],
    command => 'bash -c "nova flavor-create --is-public true m1.micro auto 64 0 1"',
    unless  => 'bash -c "nova flavor-list | grep -q m1.micro"',
    tries => 10,
    try_sleep => 2,
    require => Class['nova'],
  }

  Haproxy_backend_status <| |>    -> Exec<| title == 'create-m1.micro-flavor' |>

  if ! $use_neutron {
    nova_floating_range { $floating_ips_range:
      ensure          => 'present',
      pool            => 'nova',
      username        => $access_hash[user],
      api_key         => $access_hash[password],
      auth_method     => 'password',
      auth_url        => "http://${management_vip}:5000/v2.0/",
      authtenant_name => $access_hash[tenant],
      api_retries     => 10,
    }
    Haproxy_backend_status['nova-api'] -> Nova_floating_range <| |>
  }
}

nova_config {
  'DEFAULT/teardown_unused_network_gateway': value => 'True'
}

if $sahara_hash['enabled'] {
  $scheduler_default_filters = [ 'DifferentHostFilter' ]
} else {
  $scheduler_default_filters = []
}

class { '::nova::scheduler::filter':
  cpu_allocation_ratio       => '8.0',
  disk_allocation_ratio      => '1.0',
  ram_allocation_ratio       => '1.0',
  scheduler_host_subset_size => '30',
  scheduler_default_filters  => concat($scheduler_default_filters, [ 'RetryFilter', 'AvailabilityZoneFilter', 'RamFilter', 'CoreFilter', 'DiskFilter', 'ComputeFilter', 'ComputeCapabilitiesFilter', 'ImagePropertiesFilter', 'ServerGroupAntiAffinityFilter', 'ServerGroupAffinityFilter' ])
}

# From logasy filter.pp
nova_config {
  'DEFAULT/ram_weight_multiplier':        value => '1.0'
}

