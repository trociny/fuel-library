notice('MODULAR: astute/ceph_compute.pp')

$storage_hash             = hiera('storage', {})
$controllers              = hiera('controllers')
$use_neutron              = hiera('use_neutron')
$nodes_hash               = hiera('nodes', {})
$public_vip               = hiera('public_vip')
$management_vip           = hiera('management_vip')
$use_syslog               = hiera('use_syslog', true)
$syslog_log_facility_ceph = hiera('syslog_log_facility_ceph','LOG_LOCAL0')
$keystone_hash            = hiera('keystone', {})
$internal_address         = hiera('internal_address')
# Cinder settings
$cinder_pool              = 'volumes'
# Glance settings
$glance_pool              = 'images'
#Nova Compute settings
$compute_user             = 'compute'
$compute_pool             = 'compute'


if ($storage_hash['images_ceph']) {
  $glance_backend = 'ceph'
} elsif ($storage_hash['images_vcenter']) {
  $glance_backend = 'vmware'
} else {
  $glance_backend = 'swift'
}

if (!empty(filter_nodes(hiera('nodes'), 'role', 'ceph-osd')) or
  $storage_hash['volumes_ceph'] or
  $storage_hash['images_ceph'] or
  $storage_hash['objects_ceph']
) {
  $use_ceph = true
} else {
  $use_ceph = false
}

if $use_ceph {
  $primary_mons   = $controllers
  $primary_mon    = $controllers[0]['name']

  if ($use_neutron) {
    prepare_network_config(hiera('network_scheme', {}))
    $ceph_cluster_network = get_network_role_property('storage', 'cidr')
    $ceph_public_network  = get_network_role_property('management', 'cidr')
  } else {
    $ceph_cluster_network = hiera('storage_network_range')
    $ceph_public_network = hiera('management_network_range')
  }

  class {'ceph_fuel':
    primary_mon              => $primary_mon,
    mon_hosts                => nodes_with_roles($nodes_hash, ['primary-controller',
                                                 'controller', 'ceph-mon'], 'name'),
    mon_ip_addresses         => nodes_with_roles($nodes_hash, ['primary-controller',
                                                 'controller', 'ceph-mon'], 'internal_address'),
    cluster_node_address     => $public_vip,
    osd_pool_default_size    => $storage_hash['osd_pool_size'],
    osd_pool_default_pg_num  => $storage_hash['pg_num'],
    osd_pool_default_pgp_num => $storage_hash['pg_num'],
    use_rgw                  => false,
    glance_backend           => $glance_backend,
    rgw_pub_ip               => $public_vip,
    rgw_adm_ip               => $management_vip,
    rgw_int_ip               => $management_vip,
    cluster_network          => $ceph_cluster_network,
    public_network           => $ceph_public_network,
    use_syslog               => $use_syslog,
    syslog_log_level         => hiera('syslog_log_level_ceph', 'info'),
    syslog_log_facility      => $syslog_log_facility_ceph,
    rgw_keystone_admin_token => $keystone_hash['admin_token'],
    ephemeral_ceph           => $storage_hash['ephemeral_ceph']
  }


  service { $::ceph_fuel::params::service_nova_compute :}

  ceph_fuel::pool {$compute_pool:
    user          => $compute_user,
    acl           => "mon 'allow r' osd 'allow class-read object_prefix rbd_children, allow rwx pool=${cinder_pool}, allow rx pool=${glance_pool}, allow rwx pool=${compute_pool}'",
    keyring_owner => 'nova',
    pg_num        => $storage_hash['pg_num'],
    pgp_num       => $storage_hash['pg_num'],
  }

  include ceph_fuel::nova_compute

  if ($storage_hash['ephemeral_ceph']) {
     include ceph_fuel::ephemeral
     Class['ceph_fuel::conf'] -> Class['ceph_fuel::ephemeral'] ~>
     Service[$::ceph_fuel::params::service_nova_compute]
  }

  Class['ceph_fuel::conf'] ->
  Ceph_fuel::Pool[$compute_pool] ->
  Class['ceph_fuel::nova_compute'] ~>
  Service[$::ceph_fuel::params::service_nova_compute]

  Exec { path => [ '/bin/', '/sbin/' , '/usr/bin/', '/usr/sbin/' ],
         cwd  => '/root',
  }

}