define ceph_fuel::osds::osd () {

  $device = split($name, ':')

  ceph::osd { $device[0]:
    journal => $device[1],
  }
}
