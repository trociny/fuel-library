# Populate keyring
# XXXMG: find a better way to do this?
define ceph_fuel::keys (
  $mon_keyring      = '/etc/ceph/ceph.mon.keyring',
  $admin_keyring    = '/etc/ceph/ceph.client.admin.keyring',
  $primary_mon      = $::ceph_fuel::primary_mon,
) {
  $bootstrap_keyring = $name

  exec {'Populate client.admin keyring':
    command => $::hostname ? {
      $primary_mon => "ceph-authtool --create-keyring --gen-key --name=client.admin ${admin_keyring} --cap mon 'allow *' --cap osd 'allow *' --cap mds 'allow'",
      default => "scp ${primary_mon}:${admin_keyring} ${admin_keyring}",
    },
    creates => $admin_keyring,
  } ->

  exec {'Populate mon keyring':
    command => $::hostname ? {
      $primary_mon => "ceph-authtool --create-keyring --gen-key --name=mon. ${mon_keyring} --cap mon 'allow *'",
      default => "scp ${primary_mon}:${mon_keyring} ${mon_keyring}",
    },
    creates => $mon_keyring,
  } ->

  exec {'Populate bootstrap keyring':
    command => "/bin/true # comment to satisfy puppet syntax requirements
                set -ex
                cp ${mon_keyring} ${bootstrap_keyring}
                ceph-authtool ${bootstrap_keyring} --import-keyring ${admin_keyring}
    "
  }
}
