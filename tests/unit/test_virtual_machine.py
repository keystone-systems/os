import importlib.machinery
import importlib.util
import os
from pathlib import Path
import sys
import tempfile
import types
import unittest
from unittest import mock

class LibvirtError(Exception):
    pass


sys.modules.setdefault(
    "libvirt",
    types.SimpleNamespace(libvirtError=LibvirtError, VIR_DOMAIN_UNDEFINE_NVRAM=1),
)
SCRIPT = Path(os.environ.get("VIRTUAL_MACHINE_SCRIPT", Path(__file__).parents[2] / "bin" / "virtual-machine"))
loader = importlib.machinery.SourceFileLoader("virtual_machine", str(SCRIPT))
spec = importlib.util.spec_from_loader(loader.name, loader)
vm = importlib.util.module_from_spec(spec)
loader.exec_module(vm)


class Domain:
    def __init__(self, xml, active=False):
        self.xml = xml
        self.active = active

    def XMLDesc(self, _flags):
        return self.xml

    def isActive(self):
        return self.active

    def undefineFlags(self, _flags):
        self.undefined = True

    def create(self):
        self.started = True


class Connection:
    def __init__(self, domain):
        self.domain = domain

    def lookupByName(self, _name):
        return self.domain

    def defineXML(self, xml):
        self.domain.xml = xml
        return self.domain


class VirtualMachineTests(unittest.TestCase):
    def test_block_xml_has_direct_raw_io(self):
        xml = vm.render_disk_xml("/dev/zvol/rpool/crypt/vms/users/alice/demo/disk0", True)
        self.assertIn("type='block'", xml)
        self.assertIn("type='raw' cache='none' io='native' discard='unmap'", xml)
        self.assertIn("<target dev='vda' bus='virtio'/>", xml)
        self.assertTrue(xml.strip().endswith("</disk>"))

    def test_file_xml_remains_qcow2(self):
        xml = vm.render_disk_xml("/tmp/demo.qcow2")
        self.assertIn("type='file'", xml)
        self.assertIn("type='qcow2'", xml)
        self.assertIn("<serial>keystone-test-disk</serial>", xml)
        self.assertTrue(xml.strip().endswith("</disk>"))

    def test_names_accept_safe_vm_and_snapshot_names(self):
        for name in ("vm", "agent.drago-1", "checkpoint_2"):
            self.assertEqual(vm.validate_name(name), name)

    def test_names_reject_dataset_syntax(self):
        for name in ("../other", "vm/snapshot", "", "bad name"):
            with self.assertRaises(ValueError):
                vm.validate_name(name)

    def test_cleanup_is_dry_run_then_explicit_apply(self):
        with tempfile.TemporaryDirectory() as directory:
            old_cwd = os.getcwd()
            try:
                os.chdir(directory)
                disk = Path("vms/demo/disk.qcow2")
                disk.parent.mkdir(parents=True)
                disk.write_bytes(b"qcow2")
                xml = f"<domain><devices><disk device='disk'><source file='{disk.resolve()}'/></disk></devices></domain>"
                conn = Connection(Domain(xml))
                vm.cleanup_qcow2(conn, "demo")
                self.assertTrue(disk.exists())
                vm.cleanup_qcow2(conn, "demo", apply=True)
                self.assertFalse(disk.exists())
            finally:
                os.chdir(old_cwd)

    def test_cleanup_refuses_unrecognized_directory(self):
        conn = Connection(Domain("<domain><devices><disk device='disk'><source file='/tmp/outside.qcow2'/></disk></devices></domain>"))
        with self.assertRaisesRegex(RuntimeError, "outside recognized VM directories"):
            vm.cleanup_qcow2(conn, "demo", apply=True)

    def test_cleanup_refuses_active_domain(self):
        conn = Connection(Domain("<domain/>", active=True))
        with self.assertRaises(RuntimeError):
            vm.cleanup_qcow2(conn, "demo", apply=True)

    def test_checkpoint_create_dispatches_for_both_backends(self):
        with mock.patch.object(vm, "run_zfs") as zfs, mock.patch.object(vm.subprocess, "run") as run:
            zfs.return_value.returncode = 0
            run.return_value.returncode = 0
            self.assertEqual(vm.checkpoint_create("zvol", "rpool/vms/demo/disk0", "clean"), 0)
            zfs.assert_called_once_with("snapshot", "-r", "rpool/vms/demo@clean", check=False)
            self.assertEqual(vm.checkpoint_create("qcow2", "/tmp/demo.qcow2", "clean"), 0)
            run.assert_called_once_with(["qemu-img", "snapshot", "-c", "clean", "/tmp/demo.qcow2"])

    def test_checkpoint_restore_dispatches_for_both_backends(self):
        with mock.patch.object(vm, "rollback_zfs_checkpoint", return_value=0) as rollback, mock.patch.object(vm.subprocess, "run") as run:
            run.return_value.returncode = 0
            self.assertEqual(vm.checkpoint_restore("zvol", "rpool/vms/demo/disk0", "clean"), 0)
            rollback.assert_called_once_with("rpool/vms/demo", "clean")
            self.assertEqual(vm.checkpoint_restore("qcow2", "/tmp/demo.qcow2", "clean"), 0)
            run.assert_called_once_with(["qemu-img", "snapshot", "-a", "clean", "/tmp/demo.qcow2"])

    def test_checkpoint_list_dispatches_for_both_backends(self):
        with mock.patch.object(vm, "run_zfs") as zfs, mock.patch.object(vm.subprocess, "run") as run:
            zfs.return_value.returncode = 0
            run.return_value.returncode = 0
            vm.checkpoint_list("zvol", "rpool/vms/demo/disk0")
            zfs.assert_called_once_with("list", "-H", "-t", "snapshot", "-o", "name", "-r", "rpool/vms/demo", check=False)
            vm.checkpoint_list("qcow2", "/tmp/demo.qcow2")
            run.assert_called_once_with(["qemu-img", "snapshot", "-l", "/tmp/demo.qcow2"], check=False)

    def test_snapshot_and_restore_require_stopped_domain(self):
        conn = Connection(Domain("<domain/>", active=True))
        with self.assertRaisesRegex(RuntimeError, "stopped for snapshots"):
            vm.snapshot_create(conn, "demo", "clean")
        with self.assertRaisesRegex(RuntimeError, "stopped for restore"):
            vm.snapshot_restore(conn, "demo", "clean")

    def test_post_install_uses_checkpoint_dispatch(self):
        xml = "<domain><os/><devices><disk device='disk'><source dev='/dev/zvol/rpool/vms/demo/disk0'/></disk></devices></domain>"
        conn = Connection(Domain(xml))
        with mock.patch.object(vm, "checkpoint_create", return_value=0) as create:
            vm.post_install_reboot(conn, "demo")
        create.assert_called_once_with("zvol", "rpool/vms/demo/disk0", "post-install")
        self.assertTrue(conn.domain.started)

    def test_reset_refuses_zvol_with_snapshots_before_undefine(self):
        xml = "<domain><devices><disk device='disk'><source dev='/dev/zvol/rpool/crypt/vms/users/alice/demo/disk0'/></disk></devices></domain>"
        domain = Domain(xml)
        conn = Connection(domain)
        result = types.SimpleNamespace(stdout="rpool/crypt/vms/users/alice/demo@manual\n")
        config = {"dataset": "rpool/crypt/vms"}
        with mock.patch.object(vm, "load_backend_config", return_value=config), mock.patch.object(vm.pwd, "getpwuid", return_value=types.SimpleNamespace(pw_name="alice")), mock.patch.object(vm, "run_zfs", return_value=result):
            with self.assertRaisesRegex(RuntimeError, "while checkpoints exist"):
                vm.reset_vm(conn, "demo")
        self.assertFalse(hasattr(domain, "undefined"))

    def test_reset_refuses_unexpected_zvol_before_undefine(self):
        xml = "<domain><devices><disk device='disk'><source dev='/dev/zvol/rpool/crypt/vms/users/bob/demo/disk0'/></disk></devices></domain>"
        domain = Domain(xml)
        result = types.SimpleNamespace(stdout="")
        with mock.patch.object(vm, "load_backend_config", return_value={"dataset": "rpool/crypt/vms"}), mock.patch.object(vm.pwd, "getpwuid", return_value=types.SimpleNamespace(pw_name="alice")), mock.patch.object(vm, "run_zfs", return_value=result):
            with self.assertRaisesRegex(RuntimeError, "outside this user's VM tree"):
                vm.reset_vm(Connection(domain), "demo")
        self.assertFalse(hasattr(domain, "undefined"))

    def test_reset_deletes_expected_snapshot_free_zvol(self):
        xml = "<domain><devices><disk device='disk'><source dev='/dev/zvol/rpool/crypt/vms/users/alice/demo/disk0'/></disk></devices></domain>"
        domain = Domain(xml)
        result = types.SimpleNamespace(stdout="", returncode=0)
        with tempfile.TemporaryDirectory() as directory:
            old_cwd = os.getcwd()
            try:
                os.chdir(directory)
                with mock.patch.object(vm, "load_backend_config", return_value={"dataset": "rpool/crypt/vms"}), mock.patch.object(vm.pwd, "getpwuid", return_value=types.SimpleNamespace(pw_name="alice")), mock.patch.object(vm, "run_zfs", return_value=result) as zfs:
                    vm.reset_vm(Connection(domain), "demo")
            finally:
                os.chdir(old_cwd)
        self.assertTrue(domain.undefined)
        self.assertIn(mock.call("destroy", "rpool/crypt/vms/users/alice/demo/disk0"), zfs.call_args_list)
        self.assertIn(mock.call("destroy", "rpool/crypt/vms/users/alice/demo"), zfs.call_args_list)


if __name__ == "__main__":
    unittest.main()
