import unittest
from fuel_test.cobbler.vm_test_case import CobblerTestCase
from fuel_test.manifest import Manifest
from fuel_test.settings import OPENSTACK_SNAPSHOT, CREATE_SNAPSHOTS


class SimpleTestCase(CobblerTestCase):
    def test_simple(self):
        manifest = Manifest().generate_openstack_simple_manifest(
            ci=self.ci(),
            controllers=self.nodes().controllers,
            use_syslog=False
        )

        Manifest().write_manifest(remote=self.remote(), manifest=manifest)

        self.validate(
            self.nodes().controllers[:1] + self.nodes().computes,
            'puppet agent --test 2>&1')
        if CREATE_SNAPSHOTS:
            self.environment().snapshot(OPENSTACK_SNAPSHOT, force=True)

if __name__ == '__main__':
    unittest.main()
