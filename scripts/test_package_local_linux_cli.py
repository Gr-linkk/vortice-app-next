#!/usr/bin/env python3
"""Synthetic packaging boundaries; mock CLI inputs do not exercise the CLI."""

from contextlib import redirect_stderr, redirect_stdout
import gzip
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import stat
import tarfile
import tempfile
import unittest
from unittest.mock import patch


SPEC = importlib.util.spec_from_file_location(
    "package_local_linux_cli", Path(__file__).with_name("package-local-linux-cli.py"))
builder = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(builder)
ROOT = builder.ROOT


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def member(name, data=b"", mode=0o644, kind=tarfile.REGTYPE, **fields):
    info = tarfile.TarInfo(name)
    info.type = kind
    info.mode = mode
    info.size = len(data) if kind == tarfile.REGTYPE else 0
    info.mtime = 123456789
    info.uid, info.gid = 123, 456
    for key, value in fields.items():
        setattr(info, key, value)
    return info, data


class PackageTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="cli-package-fixture-")
        self.base = Path(self.temporary.name)
        self.cli = self.base / "cli source λ"
        (self.cli / "distribution").mkdir(parents=True)
        # Explicit non-functional fixtures, never presented as launcher E2E.
        for relative in (
            "cli.mjs", "client.mjs", "contract.mjs", "transport.mjs",
            "distribution/entry.mjs", "distribution/vortice-agent",
        ):
            (self.cli / relative).write_bytes(f"fixture only: {relative}\n".encode())
        (self.cli / "README.md").write_text("must not enter package")
        (self.cli / "test").mkdir()
        (self.cli / "test" / "private.txt").write_text("must not enter package")
        self.help = self.cli / "distribution" / "AGENT-CLI.md"
        self.help.write_text("Synthetic fixture help.\n")
        self.archive = self.base / "original.tar.gz"
        self.output = self.base / "new distribution λ.tar.gz"
        self.original = [
            member(ROOT, mode=0o755, kind=tarfile.DIRTYPE),
            member(ROOT + "/lib", mode=0o750, kind=tarfile.DIRTYPE),
            member(ROOT + "/data", mode=0o751, kind=tarfile.DIRTYPE),
            member(ROOT + "/maintenance_local", b"mock executable\x00", 0o755),
        ]
        self.original += [member(f"{ROOT}/lib/library-{i}.so", bytes([i]) * (i + 3), 0o640)
                          for i in range(3)]
        self.original += [member(f"{ROOT}/data/asset-{i}.bin", f"asset {i} λ".encode(), 0o644)
                          for i in range(13)]
        self.write_archive(self.original)

    def tearDown(self):
        self.temporary.cleanup()

    def write_archive(self, entries):
        with tarfile.open(self.archive, "w:gz", format=tarfile.PAX_FORMAT) as archive:
            for info, data in entries:
                archive.addfile(info, io.BytesIO(data) if info.isfile() else None)

    def arguments(self, **changes):
        arguments = dict(app_archive=self.archive, app_sha256=digest(self.archive),
                         app_source="b" * 40, cli_source=self.cli, cli_revision="c" * 40,
                         help_file=self.help, output=self.output)
        arguments.update(changes)
        return arguments

    def run_package(self, **changes):
        return builder.package(**self.arguments(**changes))

    def assert_refused(self, **changes):
        before = digest(self.archive)
        with self.assertRaises((builder.PackageError, OSError, EOFError, ValueError, tarfile.TarError)):
            self.run_package(**changes)
        self.assertEqual(digest(self.archive), before)
        self.assertFalse(self.output.exists())
        self.assertEqual(list(self.base.glob(".vortice-cli-package-*")), [])

    def test_preserves_17_original_files_modes_directories_and_fixed_inventory(self):
        original_digest = digest(self.archive)
        receipt = self.run_package()
        self.assertEqual(receipt["application_files"], 17)
        self.assertEqual(receipt["runtime_files"], 7)
        self.assertEqual(receipt["sha256"], digest(self.output))
        self.assertEqual(receipt["bytes"], self.output.stat().st_size)
        self.assertEqual(digest(self.archive), original_digest)
        with tarfile.open(self.output, "r:gz") as archive:
            entries = {item.name: item for item in archive}
            for original, data in self.original:
                actual = entries[original.name]
                self.assertEqual(actual.mode, original.mode)
                self.assertEqual(actual.isdir(), original.isdir())
                self.assertEqual(actual.mtime, 0)
                if original.isfile():
                    self.assertEqual(archive.extractfile(actual).read(), data)
            manifest = json.load(archive.extractfile(ROOT + "/agent-cli/distribution/bundle.json"))
            self.assertEqual(set(manifest), {
                "package_format", "protocol_version", "client_version", "client_source_revision",
                "application_source_revision", "application_archive_sha256", "files"})
            self.assertEqual(manifest["package_format"], "vortice-linux-cli-v1")
            self.assertEqual(manifest["protocol_version"], 1)
            self.assertEqual(manifest["client_version"], "0.1.0")
            self.assertEqual(manifest["client_source_revision"], "c" * 40)
            self.assertEqual(manifest["application_source_revision"], "b" * 40)
            self.assertEqual(manifest["application_archive_sha256"], original_digest)
            self.assertEqual(set(manifest["files"]), set(builder.RUNTIME_INPUTS))
            for relative, record in manifest["files"].items():
                actual = entries[ROOT + "/" + relative]
                data = archive.extractfile(actual).read()
                self.assertEqual(set(record), {"sha256", "bytes", "mode"})
                self.assertEqual(record, {"sha256": hashlib.sha256(data).hexdigest(),
                                          "bytes": len(data), "mode": actual.mode})
                self.assertEqual(actual.mode, 0o755 if relative == "bin/vortice-agent" else 0o644)
            expected = {item.name for item, _ in self.original}
            expected |= {ROOT + "/" + name for name in builder.RUNTIME_INPUTS}
            expected |= {ROOT + "/" + name for name in (
                "bin", "agent-cli", "agent-cli/distribution", "agent-cli/distribution/bundle.json")}
            self.assertEqual(set(entries), expected)
        self.assertEqual(stat.S_IMODE(self.output.stat().st_mode), 0o600)

    def test_repeated_new_outputs_are_byte_identical(self):
        self.run_package()
        second = self.base / "second.tar.gz"
        self.run_package(output=second)
        self.assertEqual(self.output.read_bytes(), second.read_bytes())
        self.assertEqual(self.output.read_bytes()[4:8], b"\x00\x00\x00\x00")

    def test_existing_file_directory_and_dangling_link_are_preserved(self):
        for kind in ("file", "directory", "symlink"):
            with self.subTest(kind=kind):
                output = self.base / kind
                if kind == "file":
                    output.write_bytes(b"sentinel")
                elif kind == "directory":
                    output.mkdir()
                else:
                    output.symlink_to(self.base / "missing")
                with self.assertRaises(builder.PackageError):
                    self.run_package(output=output)
                if kind == "file":
                    self.assertEqual(output.read_bytes(), b"sentinel")
                elif kind == "directory":
                    self.assertTrue(output.is_dir())
                else:
                    self.assertTrue(output.is_symlink())
        self.assertEqual(list(self.base.glob(".vortice-cli-package-*")), [])

    def test_competing_publication_does_not_replace_its_sentinel(self):
        link = os.link
        def compete(source, target, **options):
            Path(target).write_bytes(b"competing writer")
            return link(source, target, **options)
        with patch.object(builder.os, "link", side_effect=compete):
            with self.assertRaises(FileExistsError):
                self.run_package()
        self.assertEqual(self.output.read_bytes(), b"competing writer")
        self.assertEqual(list(self.base.glob(".vortice-cli-package-*")), [])

    def test_failed_writer_removes_only_its_temporary_file(self):
        sentinel = self.base / "unrelated"
        sentinel.write_bytes(b"keep")
        def fail(*args):
            args[-1].write(b"partial output")
            raise OSError("synthetic failure")
        with patch.object(builder, "_write", side_effect=fail):
            self.assert_refused()
        self.assertEqual(sentinel.read_bytes(), b"keep")

    def test_wrong_app_digest_and_invalid_revision_are_refused(self):
        for changes in ({"app_sha256": "0" * 64}, {"app_sha256": "A" * 64},
                        {"app_source": "b" * 39}, {"cli_revision": "../private"}):
            with self.subTest(changes=changes):
                self.assert_refused(**changes)

    def test_missing_or_empty_required_sources_are_refused(self):
        for relative in ("cli.mjs", "client.mjs", "contract.mjs", "transport.mjs",
                         "distribution/entry.mjs", "distribution/vortice-agent", "distribution/AGENT-CLI.md"):
            with self.subTest(relative=relative):
                source = self.cli / relative
                data = source.read_bytes()
                source.unlink()
                self.assert_refused()
                source.write_bytes(b"")
                self.assert_refused()
                source.write_bytes(data)

    def test_each_runtime_input_accepts_512kib_and_refuses_one_extra_byte(self):
        self.assertEqual(builder.MAX_SOURCE_BYTES, 524288)
        for index, (name, (relative, _)) in enumerate(builder.RUNTIME_INPUTS.items()):
            with self.subTest(name=name):
                source = self.cli / relative if relative else self.help
                original = source.read_bytes()
                accepted = self.base / f"boundary-{index}.tar.gz"
                try:
                    source.write_bytes(b"x" * 524288)
                    self.run_package(output=accepted)
                    with tarfile.open(accepted, "r:gz") as archive:
                        actual = archive.getmember(ROOT + "/" + name)
                        self.assertEqual(actual.size, 524288)
                        self.assertEqual(archive.extractfile(actual).read(), b"x" * 524288)
                    source.write_bytes(b"x" * 524289)
                    self.assert_refused()
                finally:
                    source.write_bytes(original)

    def test_symlink_source_help_archive_parent_and_output_parent_are_refused(self):
        source = self.cli / "client.mjs"
        original = source.read_bytes()
        source.unlink()
        source.symlink_to(self.cli / "cli.mjs")
        self.assert_refused()
        source.unlink()
        source.write_bytes(original)
        help_link = self.base / "help-link"
        help_link.symlink_to(self.help)
        self.assert_refused(help_file=help_link)
        archive_link = self.base / "archive-link"
        archive_link.symlink_to(self.archive)
        self.assert_refused(app_archive=archive_link)
        parent = self.base / "parent-link"
        parent.symlink_to(self.base, target_is_directory=True)
        self.assert_refused(cli_source=parent / self.cli.name)
        self.assert_refused(output=parent / self.output.name)

    def test_paths_outside_root_traversal_and_reserved_names_are_refused(self):
        names = ["/absolute", "outside/file", ROOT + "/../escape", ROOT + "/./file",
                 ROOT + "//file", ROOT + "/a\\b", ROOT + "/control\nname",
                 ROOT + "/bin", ROOT + "/agent-cli/file", ROOT + "/AGENT-CLI.md"]
        for name in names:
            with self.subTest(name=name):
                self.write_archive(self.original + [member(name, b"malicious")])
                self.assert_refused()

    def test_duplicate_files_and_directories_are_refused(self):
        for extra in (member(ROOT + "/maintenance_local", b"replacement"),
                      member(ROOT + "/lib/", kind=tarfile.DIRTYPE)):
            self.write_archive(self.original + [extra])
            self.assert_refused()

    def test_links_devices_fifo_contiguous_and_sparse_members_are_refused(self):
        for kind in (tarfile.SYMTYPE, tarfile.LNKTYPE, tarfile.CHRTYPE, tarfile.BLKTYPE,
                     tarfile.FIFOTYPE, tarfile.CONTTYPE, tarfile.GNUTYPE_SPARSE):
            with self.subTest(kind=kind):
                self.write_archive(self.original + [member(ROOT + "/unsafe", kind=kind,
                                                          linkname="/outside" if kind in (tarfile.SYMTYPE, tarfile.LNKTYPE) else "")])
                self.assert_refused()

    def test_special_modes_and_missing_directory_ancestry_are_refused(self):
        for extra in (member(ROOT + "/setuid", b"x", 0o4755),
                      member(ROOT + "/missing/file", b"x"),
                      member(ROOT + "/maintenance_local/child", b"x")):
            self.write_archive(self.original + [extra])
            self.assert_refused()
        self.write_archive(self.original[1:])
        self.assert_refused()

    def test_pax_traversal_and_sparse_extensions_are_refused(self):
        for headers in ({"path": ROOT + "/../escape"}, {"GNU.sparse.map": "0,1"},
                        {"GNU.sparse.size": "1"},
                        {"GNU.sparse.major": "1", "GNU.sparse.minor": "0"}):
            with self.subTest(headers=headers):
                self.write_archive(self.original + [member(ROOT + "/pax", b"x", pax_headers=headers)])
                self.assert_refused()

    def test_metadata_and_nested_extension_headers_are_bounded(self):
        self.write_archive(self.original + [member(ROOT + "/metadata", b"x",
                                                  pax_headers={"comment": "x" * builder.MAX_METADATA_BYTES})])
        self.assert_refused()
        raw = b"".join(member("pax", kind=tarfile.XHDTYPE)[0].tobuf() for _ in range(20))
        self.archive.write_bytes(gzip.compress(raw + b"\0" * 1024))
        self.assert_refused()

    def test_compressed_member_total_source_and_count_limits_are_bounded(self):
        for constant, limit in (("MAX_ARCHIVE_BYTES", 1), ("MAX_FILE_BYTES", 1),
                                ("MAX_TOTAL_BYTES", 1), ("MAX_SOURCE_BYTES", 1),
                                ("MAX_MEMBERS", 2), ("MAX_UNCOMPRESSED_BYTES", 100)):
            with self.subTest(constant=constant), patch.object(builder, constant, limit):
                self.assert_refused()

    def test_oversize_declared_member_is_refused_before_payload_read(self):
        info, _ = member(ROOT + "/huge")
        info.size = builder.MAX_FILE_BYTES + 1
        raw = member(ROOT, kind=tarfile.DIRTYPE)[0].tobuf() + info.tobuf() + b"\0" * 1024
        self.archive.write_bytes(gzip.compress(raw))
        self.assert_refused()

    def test_truncated_gzip_bad_crc_and_nonzero_trailing_data_are_refused(self):
        original = self.archive.read_bytes()
        corrupted = bytearray(original)
        corrupted[-8] ^= 1
        for data in (original[:-6], bytes(corrupted), gzip.compress(gzip.decompress(original) + b"another archive")):
            with self.subTest(size=len(data)):
                self.archive.write_bytes(data)
                self.assert_refused()

    def test_cli_failure_message_never_echoes_private_path_or_exception(self):
        stderr, stdout = io.StringIO(), io.StringIO()
        arguments = self.arguments(app_archive=self.base / "private-secret-do-not-echo")
        argv = [part for key, value in arguments.items() for part in ("--" + key.replace("_", "-"), str(value))]
        with redirect_stderr(stderr), redirect_stdout(stdout):
            result = builder.main(argv)
        self.assertEqual(result, 1)
        self.assertEqual(stderr.getvalue(), builder.FAILURE + "\n")
        self.assertEqual(stdout.getvalue(), "")
        stderr = io.StringIO()
        with redirect_stderr(stderr), self.assertRaises(SystemExit):
            builder.main(["--private-secret-do-not-echo"])
        self.assertEqual(stderr.getvalue(), builder.FAILURE + "\n")


if __name__ == "__main__":
    unittest.main()
