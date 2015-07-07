# ceph configuration and resource relations
# TODO: split ceph module to submodules instead of using case with roles

class ceph_fuel (
      # General settings
      $mon_hosts,
      $mon_ip_addresses,
      $cluster_node_address               = $::ipaddress, #This should be the cluster service address
      $primary_mon                        = $::hostname, #This should be the first controller
      $osd_devices                        = split($::osd_devices_list, ' '),
      $use_ssl                            = false,
      $use_rgw                            = false,

      # ceph.conf Global settings
      $auth_supported                     = 'cephx',
      $osd_journal_size                   = '2048',
      $osd_mkfs_type                      = 'xfs',
      $osd_pool_default_size              = undef,
      $osd_pool_default_min_size          = '1',
      $osd_pool_default_pg_num            = undef,
      $osd_pool_default_pgp_num           = undef,
      $cluster_network                    = undef,
      $public_network                     = undef,

      #ceph.conf osd settings
      $osd_max_backfills                  = '1',
      $osd_recovery_max_active            = '1',

      #RBD client settings
      $rbd_cache                          = true,
      $rbd_cache_writethrough_until_flush = true,

      # RadosGW settings
      $rgw_host                           = $::hostname,
      $rgw_port                           = '6780',
      $swift_endpoint_port                = '8080',
      $rgw_keyring_path                   = '/etc/ceph/keyring.radosgw.gateway',
      $rgw_socket_path                    = '/tmp/radosgw.sock',
      $rgw_log_file                       = '/var/log/ceph/radosgw.log',
      $rgw_use_keystone                   = true,
      $rgw_use_pki                        = false,
      $rgw_keystone_url                   = "${cluster_node_address}:35357",
      $rgw_keystone_admin_token           = undef,
      $rgw_keystone_token_cache_size      = '10',
      $rgw_keystone_accepted_roles        = '_member_, Member, admin, swiftoperator',
      $rgw_keystone_revocation_interval   = $::ceph_fuel::rgw_use_pki ? { false => 1000000, default => 60},
      $rgw_data                           = '/var/lib/ceph/radosgw',
      $rgw_dns_name                       = "*.${::domain}",
      $rgw_print_continue                 = true,
      $rgw_nss_db_path                    = '/etc/ceph/nss',

      # Keystone settings
      $rgw_pub_ip                         = $cluster_node_address,
      $rgw_adm_ip                         = $cluster_node_address,
      $rgw_int_ip                         = $cluster_node_address,

      # Cinder settings
      $volume_driver                      = 'cinder.volume.drivers.rbd.RBDDriver',
      $glance_api_version                 = '2',
      $cinder_user                        = 'volumes',
      $cinder_pool                        = 'volumes',
      # TODO: generate rbd_secret_uuid
      $rbd_secret_uuid                    = 'a5d0dd94-57c4-ae55-ffe0-7e3732a24455',

      # Cinder Backup settings
      $cinder_backup_user                 = 'backups',
      $cinder_backup_pool                 = 'backups',

      # Glance settings
      $glance_backend                     = 'ceph',
      $glance_user                        = 'images',
      $glance_pool                        = 'images',
      $show_image_direct_url              = 'True',

      # Compute settings
      $compute_user                       = 'compute',
      $compute_pool                       = 'compute',
      $libvirt_images_type                = 'rbd',
      $ephemeral_ceph                     = false,

      # Log settings
      $use_syslog                         = false,
      $syslog_log_facility                = 'daemon',
      $syslog_log_level                   = 'info',
) {

  Exec { path => [ '/bin/', '/sbin/' , '/usr/bin/', '/usr/sbin/' ],
         cwd  => '/root',
  }

  # Re-enable ceph_fuel::yum if not using a Fuel iso with Ceph packages
  #include ceph_fuel::yum

  if hiera('role') =~ /controller|ceph|compute|cinder/ {
    # the regex above includes all roles that require ceph.conf
    include ceph_fuel::ssh
    include ceph_fuel::params
    include ceph_fuel::conf
    Class[['ceph_fuel::ssh', 'ceph_fuel::params']] -> Class['ceph_fuel::conf']
  }

  if hiera('role') =~ /controller|ceph/ {
    service {'ceph':
      ensure  => 'running',
      enable  => true,
      require => Class['ceph_fuel::conf']
    }
    Package<| title == 'ceph' |> ~> Service<| title == 'ceph' |>
    if !defined(Service['ceph']) {
      notify{ "Module ${module_name} cannot notify service ceph on packages update": }
    }
  }

  case hiera('role') {
    'primary-controller', 'controller', 'ceph-mon': {
      include ceph_fuel::mon

      Class['ceph_fuel::conf'] -> Class['ceph_fuel::mon'] ->
      Service['ceph']

      if ($::ceph_fuel::use_rgw) {
        include ceph_fuel::radosgw
        Class['ceph_fuel::mon'] ->
        Class['ceph_fuel::radosgw'] ~>
        Service['ceph']
        if defined(Class['::keystone']){
          Class['::keystone'] -> Class['ceph_fuel::radosgw']
        }
      }
    }

    'ceph-osd': {
      if ! empty($osd_devices) {
        include ceph_fuel::osds
        Class['ceph_fuel::conf'] -> Class['ceph_fuel::osds'] ~> Service['ceph']
      }
    }

    'ceph-mds': { include ceph_fuel::mds }

    default: {}
  }
}
