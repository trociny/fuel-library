# Enable RBD backend for ephemeral volumes
class ceph_fuel::ephemeral (
  $rbd_secret_uuid     = $::ceph_fuel::rbd_secret_uuid,
  $libvirt_images_type = $::ceph_fuel::libvirt_images_type,
  $pool                = $::ceph_fuel::compute_pool,
) {

  nova_config {
    'libvirt/images_type':      value => $libvirt_images_type;
    'libvirt/inject_key':       value => false;
    'libvirt/inject_partition': value => '-2';
    'libvirt/images_rbd_pool':  value => $pool;
  }
}
