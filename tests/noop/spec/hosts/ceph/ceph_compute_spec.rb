require 'spec_helper'
require 'shared-examples'
manifest = 'ceph_fuel/ceph_compute.pp'

describe manifest do
  shared_examples 'catalog' do
    storage_hash = Noop.hiera 'storage'

    if (storage_hash['images_ceph'] or storage_hash['objects_ceph'] or storage_hash['objects_ceph'])
      it { should contain_class('ceph_fuel').with(
           'osd_pool_default_size'    => storage_hash['osd_pool_size'],
           'osd_pool_default_pg_num'  => storage_hash['pg_num'],
           'osd_pool_default_pgp_num' => storage_hash['pg_num'],)
         }
      it { should contain_class('ceph_fuel::conf') }

      it { should contain_ceph__pool('compute').with(
          'pg_num'        => storage_hash['pg_num'],
          'pgp_num'       => storage_hash['pg_num'],)
        }

      it { should contain_ceph__pool('compute').that_requires('Class[ceph_fuel::conf]') }
      it { should contain_ceph__pool('compute').that_comes_before('Class[ceph_fuel::nova_compute]') }
      it { should contain_class('ceph_fuel::nova_compute').that_requires('Ceph_fuel::Pool[compute]') }

      if storage_hash['ephemeral_ceph']
        it { should contain_class('ceph_fuel::ephemeral') }
        it { should contain_class('ceph_fuel::conf').that_comes_before('Class[ceph_fuel::ephemeral]') }
      end
    end

  end
  test_ubuntu_and_centos manifest
end
