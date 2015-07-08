# Ceph_fuel::mds will install mds server if invoked

class ceph_fuel::mds (
) {
  if $::mds_server {

    class { 'ceph::mds': }
  }
}
