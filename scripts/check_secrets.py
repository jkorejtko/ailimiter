#!/usr/bin/env python3
"""Check reachable Git history and the working tree without printing secret values.

This intentionally small pattern scanner complements provider-side secret scanning;
it cannot prove the absence of every possible credential.
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PATTERNS = {
    "provider key": rb"(?:sk-(?:ant-(?:api[0-9]+|sid[0-9]+|oat[0-9]+)-[A-Za-z0-9_-]{20,}|proj-[A-Za-z0-9_-]{20,}|[A-Za-z0-9_-]{30,})|pplx-[A-Za-z0-9_-]{20,}|AIza[0-9A-Za-z_-]{30,})",
    "JWT": rb"eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}",
    "GitHub token": rb"(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,})",
    "private key": rb"-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----",
    "Google refresh token": rb"1//[A-Za-z0-9_-]{40,}",
}


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT)


def scan(data, label):
    findings = 0
    for kind, pattern in PATTERNS.items():
        for match in re.finditer(pattern, data):
            line = data[:match.start()].count(b"\n") + 1
            print(f"{label}:{line}: possible {kind} (value suppressed)")
            findings += 1
    return findings


def main():
    findings = 0
    blobs = 0
    for entry in git("rev-list", "--objects", "--all").splitlines():
        parts = entry.split(b" ", 1)
        if len(parts) != 2:
            continue
        oid, name = parts
        if git("cat-file", "-t", oid.decode()).strip() != b"blob":
            continue
        blobs += 1
        findings += scan(git("cat-file", "blob", oid.decode()), f"{oid.decode()[:12]}:{name.decode(errors='replace')}")
    for raw_name in git("ls-files", "-z", "--cached", "--others", "--exclude-standard").split(b"\0"):
        if not raw_name:
            continue
        name = raw_name.decode(errors="surrogateescape")
        file = ROOT / name
        if file.is_file() and not file.is_symlink():
            findings += scan(file.read_bytes(), name)
    print(f"Scanned {blobs} historical blobs and working-tree files; {findings} possible secrets.")
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
