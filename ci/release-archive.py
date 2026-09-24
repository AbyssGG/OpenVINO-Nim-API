#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0

"""Build and verify the release archives, from metadata rather than from a clock.

The archive base name is
`openvino-nim-{version}-{date}-ov{openvino}` with every dot replaced by a
hyphen. For version `0.1.0` released on `2026-9-24` against OpenVINO `2026.4.0`
that is `openvino-nim-0-1-0-2026-9-24-ov2026-4-0`.

Two rules this script exists to enforce:

*The date is an input, never the runner's clock.* `--date` is required. A
release rebuilt next week from the same commit must produce the same file name,
and a name derived from `date(1)` on the runner cannot do that. There is
deliberately no default.

*Everything is verified after the fact.* The archives are read back and checked
for a single top-level directory equal to the base name, for the absence of any
OpenVINO runtime or SDK file, and for a checksum that matches the sidecar. A
generator that is only checked by reading its own source is not checked.

The archives come from `git archive`, so their contents are exactly one commit
and nothing from the working tree. That also makes them byte-reproducible for a
given commit, which is what lets two runs be compared.

Usage:
    python ci/release-archive.py --date 2026-9-24 --dry-run
    python ci/release-archive.py --date 2026-9-24 --out-dir build/release
    python ci/release-archive.py --date 2026-9-24 --expect-tag v0.1.0 ...
"""

from __future__ import annotations

import argparse
import hashlib
import pathlib
import re
import subprocess
import sys
import tarfile
import zipfile

VERSION_MODULE = pathlib.Path("src/openvino/version.nim")

# Extensions that must never appear in a source archive. The release ships this
# package's sources; shipping an OpenVINO library or a model would change both
# the size and the licensing picture.
FORBIDDEN_SUFFIXES = (
    ".dll", ".so", ".dylib", ".lib", ".a", ".exe", ".pdb", ".obj", ".o",
    ".whl", ".blob", ".onnx", ".pdmodel", ".tflite", ".gguf", ".safetensors",
    ".bin",
)

# Files that are allowed despite matching above. The test fixture is IR XML and
# has no weights file, so this stays empty; it exists so that adding an
# exception is a visible decision rather than a loosened pattern.
ALLOWED_EXCEPTIONS: tuple[str, ...] = ()

DATE_PATTERN = re.compile(r"^\d{4}-\d{1,2}-\d{1,2}$")


def read_constant(name: str) -> str:
    if not VERSION_MODULE.exists():
        raise SystemExit(
            f"{VERSION_MODULE} not found; run this from the repository root"
        )
    text = VERSION_MODULE.read_text(encoding="utf-8")
    match = re.search(rf'{name}\*\s*=\s*"([^"]+)"', text)
    if not match:
        raise SystemExit(f"cannot read {name} from {VERSION_MODULE}")
    return match.group(1)


def base_name(version: str, date: str, openvino: str) -> str:
    """Return the archive base name for this metadata.

    Kept as one small function so the naming rule has a single definition and
    the tests below can call it directly.
    """
    return (
        f"openvino-nim-{version.replace('.', '-')}-{date}"
        f"-ov{openvino.replace('.', '-')}"
    )


def digest(path: pathlib.Path) -> str:
    sha = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            sha.update(chunk)
    return sha.hexdigest()


def git(*arguments: str) -> str:
    finished = subprocess.run(
        ["git", *arguments],
        capture_output=True,
        text=True,
        check=True,
    )
    return finished.stdout.strip()


def build(out_dir: pathlib.Path, base: str) -> list[pathlib.Path]:
    out_dir.mkdir(parents=True, exist_ok=True)
    produced: list[pathlib.Path] = []
    for extension, form in ((".zip", "zip"), (".tar.gz", "tar.gz")):
        archive = out_dir / f"{base}{extension}"
        git(
            "archive",
            f"--format={form}",
            f"--prefix={base}/",
            "-o",
            str(archive),
            "HEAD",
        )
        produced.append(archive)
        print(f"built {archive} ({archive.stat().st_size} bytes)")
    return produced


def entries(archive: pathlib.Path) -> list[str]:
    if archive.name.endswith(".zip"):
        with zipfile.ZipFile(archive) as bundle:
            return bundle.namelist()
    with tarfile.open(archive, "r:gz") as bundle:
        return bundle.getnames()


def verify(archive: pathlib.Path, base: str) -> list[str]:
    problems: list[str] = []
    names = entries(archive)
    if not names:
        return [f"{archive.name} is empty"]

    roots = {name.split("/", 1)[0] for name in names if name}
    if roots != {base}:
        problems.append(
            f"{archive.name} has top-level entries {sorted(roots)}, "
            f"expected exactly ['{base}']"
        )

    for name in names:
        if name.endswith("/"):
            continue
        relative = name.split("/", 1)[1] if "/" in name else name
        if relative in ALLOWED_EXCEPTIONS:
            continue
        lowered = relative.lower()
        for suffix in FORBIDDEN_SUFFIXES:
            if lowered.endswith(suffix):
                problems.append(
                    f"{archive.name} contains {relative}, whose extension "
                    f"{suffix} must never be in a source archive"
                )
    return problems


def write_sidecar(archive: pathlib.Path) -> pathlib.Path:
    sidecar = archive.with_name(archive.name + ".sha256")
    value = digest(archive)
    # The two-space form `sha256sum -c` expects, so a consumer can verify with
    # the tool they already have.
    sidecar.write_text(f"{value}  {archive.name}\n", encoding="utf-8")
    print(f"wrote {sidecar.name}: {value}")
    return sidecar


def verify_sidecar(archive: pathlib.Path) -> list[str]:
    sidecar = archive.with_name(archive.name + ".sha256")
    if not sidecar.exists():
        return [f"{sidecar.name} is missing"]
    recorded = sidecar.read_text(encoding="utf-8").split()[0]
    actual = digest(archive)
    if recorded != actual:
        return [
            f"{sidecar.name} records {recorded} but {archive.name} hashes to "
            f"{actual}"
        ]
    return []


def self_test() -> int:
    """Check the naming rule against the example the plan states."""
    expected = "openvino-nim-0-1-0-2026-9-24-ov2026-4-0"
    produced = base_name("0.1.0", "2026-9-24", "2026.4.0")
    if produced != expected:
        print(f"naming rule broken: {produced} != {expected}", file=sys.stderr)
        return 1
    print(f"naming rule matches the documented example: {produced}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--date",
        help="release date as YYYY-M-D. Required: the runner's clock is "
             "never consulted",
    )
    parser.add_argument("--out-dir", type=pathlib.Path, default=pathlib.Path("build/release"))
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="build and verify, and say plainly that nothing is uploaded",
    )
    parser.add_argument(
        "--expect-tag",
        help="require this Git tag to match the version, for the release job",
    )
    parser.add_argument(
        "--print-name",
        action="store_true",
        help="print the base name and exit",
    )
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="check the naming rule against the documented example and exit",
    )
    arguments = parser.parse_args()

    if arguments.self_test:
        return self_test()

    if not arguments.date:
        parser.error("--date is required; this script never reads the clock")
    if not DATE_PATTERN.match(arguments.date):
        parser.error(f"--date must look like YYYY-M-D, got {arguments.date!r}")

    version = read_constant("PackageVersion")
    openvino = read_constant("TargetOpenVinoVersion")
    base = base_name(version, arguments.date, openvino)

    if arguments.print_name:
        print(base)
        return 0

    print(f"package  : {read_constant('PackageName')} {version}")
    print(f"openvino : {openvino}")
    print(f"date     : {arguments.date} (supplied, not read from the clock)")
    print(f"base name: {base}")
    print(f"commit   : {git('rev-parse', 'HEAD')}")

    problems: list[str] = []

    if arguments.expect_tag:
        expected_tag = f"v{version}"
        if arguments.expect_tag != expected_tag:
            problems.append(
                f"tag {arguments.expect_tag} does not match the package "
                f"version; expected {expected_tag}"
            )
        expected_title = f"openvino-nim {version} — {arguments.date} — OpenVINO {openvino}"
        print(f"release title should be: {expected_title}")

    if git("status", "--porcelain"):
        problems.append(
            "the working tree is not clean; git archive would ship the commit "
            "rather than what you see, which makes the archive misleading"
        )

    archives = build(arguments.out_dir, base)
    for archive in archives:
        problems.extend(verify(archive, base))
        write_sidecar(archive)
        problems.extend(verify_sidecar(archive))

    if problems:
        print()
        print("release archive problems:")
        for problem in problems:
            print("  " + problem)
        return 1

    print()
    print(f"verified {len(archives)} archives and their checksums")
    if arguments.dry_run:
        print("DRY RUN: nothing was uploaded and no release was created")
    return 0


if __name__ == "__main__":
    sys.exit(main())
