# setup Ceph monitors
class ceph_fuel::mon () {

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
    command   => "ceph mon stat | grep ${::internal_address}",
    returns   => 0,
    tries     => 60,  # This is necessary to prevent a race: mon must establish
    # a quorum before it can generate keys, observed this takes upto 15 seconds
    # Keys must exist prior to other commands running
    try_sleep => 1,
  }
}
