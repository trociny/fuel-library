# prepare and bring online the devices listed in $::ceph_fuel::osd_devices
class ceph_fuel::osds (
  $devices = $::ceph_fuel::osd_devices,
){

  firewall { '011 ceph-osd allow':
    chain  => 'INPUT',
    dport  => '6800-7100',
    proto  => 'tcp',
    action => accept,
  } ->

  ceph_fuel::osds::osd{ $devices: }

}
