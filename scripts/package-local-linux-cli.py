#!/usr/bin/env python3
"""Add the reviewed source CLI to a digest-pinned Linux app archive.

Inputs are never extracted. Output publication is atomic and never replaces a
path. This builder deliberately copies only the seven runtime/help inputs.
"""

import argparse
from contextlib import contextmanager
import gzip
import hashlib
import io
import json
import os
from pathlib import Path
import re
import stat
import sys
import tarfile
import tempfile


ROOT = "vortice-local-maintenance"
MAX_ARCHIVE_BYTES = 512 * 1024 * 1024
MAX_FILE_BYTES = 256 * 1024 * 1024
MAX_TOTAL_BYTES = 512 * 1024 * 1024
MAX_MEMBERS = 4096
MAX_METADATA_BYTES = 64 * 1024
MAX_SOURCE_BYTES = 2 * 1024 * 1024
MAX_UNCOMPRESSED_BYTES = MAX_TOTAL_BYTES + 16 * 1024 * 1024
FAILURE = "Local CLI distribution could not be safely packaged."
RUNTIME_INPUTS = {
    "bin/vortice-agent": ("distribution/vortice-agent", 0o755),
    "agent-cli/cli.mjs": ("cli.mjs", 0o644),
    "agent-cli/client.mjs": ("client.mjs", 0o644),
    "agent-cli/contract.mjs": ("contract.mjs", 0o644),
    "agent-cli/transport.mjs": ("transport.mjs", 0o644),
    "agent-cli/distribution/entry.mjs": ("distribution/entry.mjs", 0o644),
    "AGENT-CLI.md": (None, 0o644),
}
RESERVED = {"bin", "agent-cli", "AGENT-CLI.md"}


class PackageError(Exception):
    """An input or publication failed the distribution boundary."""


def _require(condition):
    if not condition:
        raise PackageError(FAILURE)


def _canonical(path, *, directory=False):
    path = Path(path)
    _require(path.is_absolute() and path.resolve(strict=True) == path)
    info = path.lstat()
    _require(stat.S_ISDIR(info.st_mode) if directory else stat.S_ISREG(info.st_mode))
    return path


def _open_regular(path, maximum):
    path = _canonical(path)
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC)
    try:
        info = os.fstat(fd)
        _require(stat.S_ISREG(info.st_mode) and 0 <= info.st_size <= maximum)
        return os.fdopen(fd, "rb")
    except BaseException:
        os.close(fd)
        raise


def _digest(file, maximum=MAX_ARCHIVE_BYTES):
    file.seek(0)
    value = hashlib.sha256()
    total = 0
    while chunk := file.read(1024 * 1024):
        total += len(chunk)
        _require(total <= maximum)
        value.update(chunk)
    file.seek(0)
    return value.hexdigest()


class _BoundedReader:
    def __init__(self, file):
        self.file = file
        self.bytes_read = 0

    def read(self, size=-1):
        _require(0 <= size <= MAX_UNCOMPRESSED_BYTES)
        result = self.file.read(size)
        self.bytes_read += len(result)
        _require(self.bytes_read <= MAX_UNCOMPRESSED_BYTES)
        return result


class _BoundedTarInfo(tarfile.TarInfo):
    # tarfile processes extension headers before yielding a member. Bound those
    # allocations here, and reject sparse extensions before their map parsers.
    def _proc_member(self, archive):
        extension = self.type in (
            tarfile.XHDTYPE, tarfile.XGLTYPE, tarfile.SOLARIS_XHDTYPE,
            tarfile.GNUTYPE_LONGNAME,
        )
        if extension:
            _require(0 <= self.size <= MAX_METADATA_BYTES)
            depth = getattr(archive, "_cli_metadata_depth", 0)
            _require(depth < 16)
            archive._cli_metadata_depth = depth + 1
        else:
            _require(self.type in (tarfile.REGTYPE, tarfile.AREGTYPE, tarfile.DIRTYPE))
        try:
            return super()._proc_member(archive)
        finally:
            if extension:
                archive._cli_metadata_depth -= 1

    def _proc_gnusparse_00(self, *args):
        raise PackageError(FAILURE)

    def _proc_gnusparse_01(self, *args):
        raise PackageError(FAILURE)

    def _proc_gnusparse_10(self, *args):
        raise PackageError(FAILURE)


@contextmanager
def _archive(file):
    file.seek(0)
    with gzip.GzipFile(fileobj=file, mode="rb") as compressed:
        reader = _BoundedReader(compressed)
        with tarfile.open(fileobj=reader, mode="r|", tarinfo=_BoundedTarInfo,
                          encoding="utf-8", errors="strict") as archive:
            yield archive
            # Finish gzip CRC validation and refuse another archive after the
            # first tar end marker. Consume tarfile's buffered bytes as well.
            while chunk := archive.fileobj.read(64 * 1024):
                _require(not any(chunk))


def _member(member):
    _require(member.type in (tarfile.REGTYPE, tarfile.AREGTYPE, tarfile.DIRTYPE))
    _require(member.sparse is None and not member.linkname)
    _require(not any(key.startswith("GNU.sparse") for key in member.pax_headers))
    name = member.name
    _require(isinstance(name, str) and 0 < len(name.encode("utf-8")) <= 4096)
    _require("\\" not in name and all(ord(char) >= 32 and ord(char) != 127 for char in name))
    if member.isdir() and name.endswith("/"):
        name = name[:-1]
    parts = name.split("/")
    _require(parts[0] == ROOT and all(part not in ("", ".", "..") for part in parts))
    _require(len(parts) > 1 or member.isdir())
    _require(len(parts) == 1 or parts[1] not in RESERVED)
    _require(isinstance(member.mode, int) and 0 <= member.mode <= 0o777)
    _require(isinstance(member.size, int) and 0 <= member.size <= MAX_FILE_BYTES)
    _require(not member.isdir() or member.size == 0)
    return name


def _scan(file):
    entries = {}
    total = 0
    with _archive(file) as archive:
        for member in archive:
            name = _member(member)
            _require(name not in entries and len(entries) < MAX_MEMBERS)
            total += member.size
            _require(total <= MAX_TOTAL_BYTES)
            digest = None
            if member.isfile():
                source = archive.extractfile(member)
                value = hashlib.sha256()
                remaining = member.size
                while remaining:
                    chunk = source.read(min(1024 * 1024, remaining))
                    _require(bool(chunk))
                    value.update(chunk)
                    remaining -= len(chunk)
                digest = value.hexdigest()
            entries[name] = (member.isdir(), member.mode, member.size, digest)
    _require(ROOT in entries and entries[ROOT][0])
    _require(any(not item[0] for item in entries.values()))
    for name in entries:
        parts = name.split("/")
        for count in range(1, len(parts)):
            parent = "/".join(parts[:count])
            _require(parent in entries and entries[parent][0])
    return entries


def _info(name, mode, size=0, directory=False):
    member = tarfile.TarInfo(name)
    member.mode = mode
    member.size = size
    member.type = tarfile.DIRTYPE if directory else tarfile.REGTYPE
    member.mtime = 0
    member.uid = member.gid = 0
    member.uname = member.gname = ""
    return member


class _HashingReader:
    def __init__(self, file):
        self.file = file
        self.digest = hashlib.sha256()

    def read(self, size):
        chunk = self.file.read(size)
        self.digest.update(chunk)
        return chunk


def _write(file, entries, runtime, manifest, output):
    with gzip.GzipFile(filename="", mode="wb", fileobj=output, mtime=0) as compressed:
        with tarfile.open(fileobj=compressed, mode="w|", format=tarfile.PAX_FORMAT,
                          encoding="utf-8", errors="strict") as destination:
            seen = set()
            with _archive(file) as archive:
                for member in archive:
                    name = _member(member)
                    _require(name in entries and name not in seen)
                    directory, mode, size, digest = entries[name]
                    _require((member.isdir(), member.mode, member.size) == (directory, mode, size))
                    seen.add(name)
                    source = _HashingReader(archive.extractfile(member)) if not directory else None
                    destination.addfile(_info(name, mode, size, directory), source)
                    _require(source is None or source.digest.hexdigest() == digest)
            _require(seen == set(entries))
            for directory in ("bin", "agent-cli", "agent-cli/distribution"):
                destination.addfile(_info(f"{ROOT}/{directory}", 0o755, directory=True))
            for name, (data, mode) in runtime.items():
                destination.addfile(_info(f"{ROOT}/{name}", mode, len(data)), io.BytesIO(data))
            data = (json.dumps(manifest, sort_keys=True, indent=2) + "\n").encode("utf-8")
            destination.addfile(_info(f"{ROOT}/agent-cli/distribution/bundle.json", 0o644, len(data)),
                                io.BytesIO(data))


def package(*, app_archive, app_sha256, app_source, cli_source, cli_revision,
            help_file, output):
    """Return a receipt after publishing one new deterministic archive."""
    _require(re.fullmatch(r"[0-9a-f]{64}", app_sha256) is not None)
    _require(re.fullmatch(r"[0-9a-f]{40}", app_source) is not None)
    _require(re.fullmatch(r"[0-9a-f]{40}", cli_revision) is not None)
    output = Path(output)
    _require(output.is_absolute() and output.name not in ("", ".", ".."))
    _canonical(output.parent, directory=True)
    _require(output.parent / output.name == output)
    try:
        output.lstat()
    except FileNotFoundError:
        pass
    else:
        raise PackageError(FAILURE)
    cli_source = _canonical(cli_source, directory=True)
    runtime = {}
    for name, (relative, mode) in RUNTIME_INPUTS.items():
        source = cli_source / relative if relative else Path(help_file)
        with _open_regular(source, MAX_SOURCE_BYTES) as file:
            data = file.read(MAX_SOURCE_BYTES + 1)
            _require(0 < len(data) <= MAX_SOURCE_BYTES)
        runtime[name] = (data, mode)
    manifest = {
        "package_format": "vortice-linux-cli-v1",
        "protocol_version": 1,
        "client_version": "0.1.0",
        "client_source_revision": cli_revision,
        "application_source_revision": app_source,
        "application_archive_sha256": app_sha256,
        "files": {name: {"sha256": hashlib.sha256(data).hexdigest(),
                         "bytes": len(data), "mode": mode}
                  for name, (data, mode) in runtime.items()},
    }
    staging = None
    try:
        with _open_regular(app_archive, MAX_ARCHIVE_BYTES) as file:
            _require(_digest(file) == app_sha256)
            entries = _scan(file)
            fd, staging = tempfile.mkstemp(prefix=".vortice-cli-package-", dir=output.parent)
            with os.fdopen(fd, "w+b") as destination:
                _write(file, entries, runtime, manifest, destination)
                _require(_digest(file) == app_sha256)
                destination.flush()
                os.fsync(destination.fileno())
                destination.seek(0)
                digest = _digest(destination, MAX_UNCOMPRESSED_BYTES + len(runtime) * MAX_SOURCE_BYTES)
                length = os.fstat(destination.fileno()).st_size
            # link() is an atomic no-replace publication, including a competing
            # writer or dangling symlink appearing after the initial check.
            os.link(staging, output, follow_symlinks=False)
            os.unlink(staging)
            staging = None
            parent_fd = os.open(output.parent, os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC)
            try:
                os.fsync(parent_fd)
            finally:
                os.close(parent_fd)
        return {"sha256": digest, "bytes": length,
                "application_files": sum(not item[0] for item in entries.values()),
                "runtime_files": len(runtime)}
    finally:
        if staging is not None:
            os.unlink(staging)


class _Parser(argparse.ArgumentParser):
    def error(self, message):
        self.exit(2, FAILURE + "\n")


def main(argv=None):
    parser = _Parser(description=__doc__)
    for name in ("app-archive", "app-sha256", "app-source", "cli-source",
                 "cli-revision", "help-file", "output"):
        parser.add_argument("--" + name, required=True)
    args = parser.parse_args(argv)
    try:
        receipt = package(**vars(args))
    except (PackageError, OSError, EOFError, ValueError, tarfile.TarError):
        print(FAILURE, file=sys.stderr)
        return 1
    print(json.dumps(receipt, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
