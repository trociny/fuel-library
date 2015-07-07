# Ceph_fuel::mds will install mds server if invoked

class ceph_fuel::mds (
) {
  if $::mds_server {
    exec { 'ceph-deploy mds create':
      command   => "ceph-deploy mds create ${::mds_server}",
      logoutput => true,
    }
  }
}
