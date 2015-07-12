# create new conf on primary Ceph MON, pull conf on all other nodes
class ceph_fuel::conf {
  if $::hostname == $::ceph_fuel::primary_mon {

    ceph_conf {
      'global/fsid':                               value => generate('/usr/bin/uuidgen');
      'global/mon_host':                           value => $::internal_address;
      'global/mon_initial_members':                value => $::hostname;
      'global/auth_supported':                     value => $::ceph_fuel::auth_supported;
      'global/osd_journal_size':                   value => $::ceph_fuel::osd_journal_size;
      'global/osd_mkfs_type':                      value => $::ceph_fuel::osd_mkfs_type;
      'global/osd_pool_default_size':              value => $::ceph_fuel::osd_pool_default_size;
      'global/osd_pool_default_min_size':          value => $::ceph_fuel::osd_pool_default_min_size;
      'global/osd_pool_default_pg_num':            value => $::ceph_fuel::osd_pool_default_pg_num;
      'global/osd_pool_default_pgp_num':           value => $::ceph_fuel::osd_pool_default_pgp_num;
      'global/cluster_network':                    value => $::ceph_fuel::cluster_network;
      'global/public_network':                     value => $::ceph_fuel::public_network;
      'global/log_to_syslog':                      value => $::ceph_fuel::use_syslog;
      'global/log_to_syslog_level':                value => $::ceph_fuel::syslog_log_level;
      'global/log_to_syslog_facility':             value => $::ceph_fuel::syslog_log_facility;
      'global/osd_max_backfills':                  value => $::ceph_fuel::osd_max_backfills;
      'global/osd_recovery_max_active':            value => $::ceph_fuel::osd_recovery_max_active;
      'client/rbd_cache':                          value => $::ceph_fuel::rbd_cache;
      'client/rbd_cache_writethrough_until_flush': value => $::ceph_fuel::rbd_cache_writethrough_until_flush;
    }

  } else {

    exec {'ceph config pull':
      command   => "scp ${primary_mon}:/etc/ceph/ceph.conf /etc/ceph/ceph.conf",
      creates   => '/etc/ceph/ceph.conf',
      tries     => 5,
      try_sleep => 2,
    }

    ceph_conf {
      'global/mon_host':                           value => join($::ceph_fuel::mon_ip_addresses, ' ');
      'global/mon_initial_members':                value => join($::ceph_fuel::mon_hosts, ' ');
      'global/cluster_network':                    value => $::ceph_fuel::cluster_network;
      'global/public_network':                     value => $::ceph_fuel::public_network;
    }

    Exec['ceph config pull'] ->
      Ceph_conf[['global/mon_host', 'global/mon_initial_members', 'global/cluster_network', 'global/public_network']]
  }
}
