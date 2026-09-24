#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0

"""Collect a failure diagnostics bundle for CI.

What a failing ABI, runtime or device job needs from a machine you cannot log
into: which OpenVINO was installed, which libraries are actually on disk, what
the loader said, and which devices the runtime could see. This collects exactly
those and nothing else.

It deliberately does **not** dump the environment. A CI environment contains
tokens, and a diagnostics artefact is readable by anyone who can read the run.
Only an allowlist of variables is reported, and only their presence and length
for anything not on it, so a missing variable is still diagnosable without its
value being printed.
"""

from __future__ import annotations

import os
import pathlib
import platform
import subprocess
import sys

# Variables whose values are safe to print: they are paths and versions that
# the job itself set, never credentials.
SAFE_VARIABLES = (
    "OPENVINO_ROOT",
    "OPENVINO_INCLUDE_DIR",
    "OPENVINO_LIB_DIR",
    "INTEL_OPENVINO_DIR",
    "LD_LIBRARY_PATH",
    "RUNNER_OS",
    "RUNNER_ARCH",
    "CI",
)

# Anything matching one of these is never printed, not even its length.
SECRET_HINTS = ("TOKEN", "SECRET", "PASSWORD", "KEY", "CREDENTIAL", "COOKIE")


def heading(text: str) -> None:
    print()
    print("=" * 70)
    print(text)
    print("=" * 70)


def run(command: list[str], timeout: int = 120) -> None:
    print(f"$ {' '.join(command)}")
    try:
        finished = subprocess.run(
            command,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
    except FileNotFoundError:
        print("  (command not found)")
        return
    except subprocess.TimeoutExpired:
        print("  (timed out)")
        return
    print(f"  exit={finished.returncode}")
    for line in (finished.stdout + finished.stderr).splitlines()[:80]:
        print("  " + line)


def report_environment() -> None:
    heading("environment, allowlisted values only")
    for name in SAFE_VARIABLES:
        print(f"{name}={os.environ.get(name, '<unset>')}")
    print()
    print("other variables are reported by name and length only:")
    for name in sorted(os.environ):
        if name in SAFE_VARIABLES:
            continue
        if any(hint in name.upper() for hint in SECRET_HINTS):
            print(f"  {name}: withheld")
            continue
        print(f"  {name}: {len(os.environ[name])} characters")


def report_host() -> None:
    heading("host")
    print("platform:", platform.platform())
    print("machine :", platform.machine())
    print("python  :", sys.version.replace("\n", " "))
    run(["nim", "--version"])
    run(["nimble", "--version"])


def report_openvino() -> None:
    heading("OpenVINO layout")
    root = os.environ.get("OPENVINO_ROOT")
    if not root:
        print("OPENVINO_ROOT is not set; nothing to inspect")
        return
    base = pathlib.Path(root)
    for relative in ("libs", "include/openvino/c"):
        directory = base / relative
        print()
        print(f"--- {directory} ---")
        if not directory.exists():
            print("  missing")
            continue
        for entry in sorted(directory.iterdir())[:60]:
            size = entry.stat().st_size if entry.is_file() else 0
            print(f"  {entry.name}  {size}")


def report_devices() -> None:
    heading("what the runtime reports, through the package itself")
    # list_devices is the example written for exactly this question. Running it
    # here means the diagnostics use the same code path a user would.
    run(
        [
            "nim",
            "c",
            "--hints:off",
            "--path:src",
            "-r",
            "examples/list_devices.nim",
        ],
        timeout=600,
    )


def main() -> int:
    report_host()
    report_environment()
    report_openvino()
    report_devices()
    print()
    print("### diagnostics complete")
    return 0


if __name__ == "__main__":
    sys.exit(main())
