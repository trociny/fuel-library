# setup Ceph monitors
class ceph_fuel::mon (
  $mon_hosts        = $::ceph_fuel::mon_hosts,
  $mon_ip_addresses = $::ceph_fuel::mon_ip_addresses,
) {

  $bootstrap_keyring = '/tmp/ceph-mon-keyring'

  firewall {'010 ceph-mon allow':
    chain  => 'INPUT',
    dport  => 6789,
    proto  => 'tcp',
    action => accept,
  } ->

  ceph_fuel::keys { $bootstrap_keyring: } ->

  ceph::mon { $::hostname:
    keyring => $bootstrap_keyring,
  } ->

  exec { "rm-keyring $bootstrap_keyring":
     command => "/bin/rm -f ${bootstrap_keyring}",
  } ->

  exec {'Wait for Ceph quorum':
    command   => 'ceph mon stat',
    returns   => 0,
    tries     => 60,  # This is necessary to prevent a race: mon must establish
    # a quorum before it can generate keys, observed this takes upto 15 seconds
    # Keys must exist prior to other commands running
    try_sleep => 1,
  }

  if $::hostname == $::ceph_fuel::primary_mon {

    # After the primary monitor has established a quorum, it is safe to
    # add other monitors to ceph.conf. All other Ceph nodes will get
    # these settings via 'ceph-deploy config pull' in ceph_fuel::conf.
    ceph_conf {
      'global/mon_host':            value => join($mon_ip_addresses, ' ');
      'global/mon_initial_members': value => join($mon_hosts, ' ');
    }

    # Has to be an exec: Puppet can't reload a service without declaring
    # an ordering relationship.
    exec {'reload Ceph for HA':
      command   => 'service ceph reload',
      subscribe => [Ceph_conf['global/mon_host'], Ceph_conf['global/mon_initial_members']]
    }

    Exec['Wait for Ceph quorum'] ->
    Ceph_conf[['global/mon_host', 'global/mon_initial_members']] ->
    Exec['reload Ceph for HA']
  }
}
