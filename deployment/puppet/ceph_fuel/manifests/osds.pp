# prepare and bring online the devices listed in $::ceph_fuel::osd_devices
class ceph_fuel::osds (
  $devices = $::ceph_fuel::osd_devices,
  $primary_mon = $::ceph_fuel::primary_mon,
  $keyring_path = '/var/lib/ceph/bootstrap-osd/ceph.keyring',
){

  firewall { '011 ceph-osd allow':
    chain  => 'INPUT',
    dport  => '6800-7100',
    proto  => 'tcp',
    action => accept,
  } ->

  # XXXMG: not sure this the best way to distribute bootstrap-osd keyring
  exec { "Populate client.bootstrap-osd keyring":
    command => "ceph auth get-or-create client.bootstrap-osd > ${keyring_path}",
    creates => $keyring_path
  } ->

  file { $keyring_path: mode => '0640', } ->

  ceph_fuel::osds::osd{ $devices: }
}
