#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0

"""Install the pinned OpenVINO runtime and headers for CI, by checksum.

Why this exists, and why it is Python rather than two shell scripts. The CI
needs the same OpenVINO on a Windows runner and a Linux runner. Writing the
download, the checksum check and the unpacking twice, once in bash and once in
PowerShell, would mean two implementations that can disagree about which
artefact was verified. This is one implementation, and the artefact it verifies
is the one it unpacks.

Why a wheel rather than the official archive. The wheel is addressed by an
immutable URL on files.pythonhosted.org with a published sha256, so the pin is
exact and auditable from this file alone. It carries the runtime libraries, the
device plugins, the frontends, oneTBB and the C headers, which is everything
the test suite needs. It is unpacked with `zipfile` and never installed into a
Python environment: nothing here imports openvino from Python, so `pip` and its
dependency resolution are not involved at all.

The pinned version is cross-checked against `src/openvino/version.nim` before
anything is downloaded, so this file cannot quietly pin a different OpenVINO
than the library claims to target.

Usage:
    python ci/install-openvino.py --dest <directory>
    python ci/install-openvino.py --print-pins
"""

from __future__ import annotations

import argparse
import hashlib
import pathlib
import platform
import re
import sys
import urllib.request
import zipfile

# The pinned OpenVINO version. Must equal TargetOpenVinoVersion in
# src/openvino/version.nim; checked below rather than trusted.
OPENVINO_VERSION = "2026.4.0"

# The upstream build number, which appears in the wheel file name and in the
# runtime's own version string. Recording it here means a wheel rebuilt under
# the same version number cannot be substituted silently.
OPENVINO_BUILD = "22959"

# One wheel per Tier 1 platform, addressed by immutable URL and verified by
# the sha256 that PyPI publishes for it. cp312 because the CI pins Python 3.12.
WHEELS = {
    "Linux": {
        "filename": (
            "openvino-2026.4.0-22959-cp312-cp312-manylinux_2_28_x86_64.whl"
        ),
        "url": (
            "https://files.pythonhosted.org/packages/09/96/"
            "106f20950f8636f23925fa9867f9b1d7d10dd20f7b0300b10f8da40fdf16/"
            "openvino-2026.4.0-22959-cp312-cp312-manylinux_2_28_x86_64.whl"
        ),
        "sha256": (
            "75245768f656afffd49078cee55b50b9501bb6778798aec3cc30e5613a86e370"
        ),
    },
    "Windows": {
        "filename": "openvino-2026.4.0-22959-cp312-cp312-win_amd64.whl",
        "url": (
            "https://files.pythonhosted.org/packages/62/95/"
            "6b1a095f865cd5a02f773590a419525ee9f9fc25770901cf461dad38aa29/"
            "openvino-2026.4.0-22959-cp312-cp312-win_amd64.whl"
        ),
        "sha256": (
            "1d64a3178e750ea35f4095dc8ee6e0492795a5cf85c0dd24593a29f8a60c209d"
        ),
    },
}

VERSION_MODULE = pathlib.Path("src/openvino/version.nim")


def pinned_version_from_library() -> str:
    """Return TargetOpenVinoVersion as the Nim source declares it."""
    if not VERSION_MODULE.exists():
        raise SystemExit(
            f"{VERSION_MODULE} not found; run this from the repository root"
        )
    text = VERSION_MODULE.read_text(encoding="utf-8")
    match = re.search(r'TargetOpenVinoVersion\*\s*=\s*"([^"]+)"', text)
    if not match:
        raise SystemExit(f"cannot read TargetOpenVinoVersion from {VERSION_MODULE}")
    return match.group(1)


def check_pin_agrees_with_library() -> None:
    """Abort unless the pinned wheel is the version the library targets.

    A CI that installs a different OpenVINO than the package pins would report
    green for a combination nobody claims to support.
    """
    declared = pinned_version_from_library()
    if declared != OPENVINO_VERSION:
        raise SystemExit(
            f"pin mismatch: this script pins OpenVINO {OPENVINO_VERSION} but "
            f"{VERSION_MODULE} declares {declared}"
        )
    for system, wheel in WHEELS.items():
        if OPENVINO_VERSION not in wheel["filename"]:
            raise SystemExit(
                f"the {system} wheel name does not contain {OPENVINO_VERSION}"
            )
        if OPENVINO_BUILD not in wheel["filename"]:
            raise SystemExit(
                f"the {system} wheel name does not contain build "
                f"{OPENVINO_BUILD}"
            )


def wheel_for_this_host() -> dict[str, str]:
    system = platform.system()
    if system not in WHEELS:
        raise SystemExit(
            f"no OpenVINO wheel is pinned for {system}. Tier 1 is "
            f"{', '.join(sorted(WHEELS))}"
        )
    return WHEELS[system]


def digest(path: pathlib.Path) -> str:
    sha = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            sha.update(chunk)
    return sha.hexdigest()


def download(url: str, destination: pathlib.Path) -> None:
    print(f"downloading {url}")
    with urllib.request.urlopen(url, timeout=300) as response:
        destination.write_bytes(response.read())
    print(f"  wrote {destination} ({destination.stat().st_size} bytes)")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--dest",
        type=pathlib.Path,
        help="directory to unpack the wheel into",
    )
    parser.add_argument(
        "--print-pins",
        action="store_true",
        help="print the pins and exit, without downloading anything",
    )
    arguments = parser.parse_args()

    check_pin_agrees_with_library()

    if arguments.print_pins:
        print(f"openvino {OPENVINO_VERSION} build {OPENVINO_BUILD}")
        for system in sorted(WHEELS):
            wheel = WHEELS[system]
            print(f"  {system}: {wheel['filename']}")
            print(f"    sha256 {wheel['sha256']}")
        return 0

    if arguments.dest is None:
        parser.error("--dest is required unless --print-pins is given")

    wheel = wheel_for_this_host()
    destination = arguments.dest.resolve()
    destination.mkdir(parents=True, exist_ok=True)
    archive = destination / wheel["filename"]

    download(wheel["url"], archive)

    produced = digest(archive)
    if produced != wheel["sha256"]:
        # Deleted, so a failed run cannot leave a file that a later step might
        # pick up and trust.
        archive.unlink(missing_ok=True)
        print("CHECKSUM MISMATCH", file=sys.stderr)
        print(f"  expected {wheel['sha256']}", file=sys.stderr)
        print(f"  produced {produced}", file=sys.stderr)
        return 1
    print(f"sha256 verified: {produced}")

    with zipfile.ZipFile(archive) as bundle:
        bundle.extractall(destination)
    archive.unlink()

    root = destination / "openvino"
    include = root / "include"
    libs = root / "libs"
    for required in (include / "openvino" / "c" / "ov_common.h", libs):
        if not required.exists():
            print(f"unpacked wheel is missing {required}", file=sys.stderr)
            return 1

    # On Linux the wheel ships no executable bit and no unversioned symlink.
    # Neither matters to this package: the loader opens the versioned name.
    print("OPENVINO_ROOT=" + str(root))
    print("OPENVINO_INCLUDE_DIR=" + str(include))
    print("OPENVINO_LIB_DIR=" + str(libs))
    return 0


if __name__ == "__main__":
    sys.exit(main())
