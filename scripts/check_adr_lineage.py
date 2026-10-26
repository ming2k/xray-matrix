#!/usr/bin/env python3
"""Fail when an ADR citation does not resolve to a canonical in-repo ADR.

Rule: `docs/dev/standards/adr.md` §1 — every `ADR-NNNN` citation in code, scripts,
or documentation must resolve to a corresponding file in `docs/adr/`. Dangling
citations or ghost references to non-existent ADRs are strictly prohibited.
"""

from __future__ import annotations

import os
import re
import subprocess
import sys

ADR_DIR = "docs/adr"
TOKEN = re.compile(r"ADR-(\d{4})")
FENCE = re.compile(r"^\s*```")


def canonical_numbers() -> set[str]:
    have = set()
    if not os.path.isdir(ADR_DIR):
        return have
    for name in os.listdir(ADR_DIR):
        m = re.match(r"(\d{4})-", name)
        if m:
            have.add(m.group(1))
    return have


def dead_tokens(text: str, have: set[str]) -> list[str]:
    return [m.group(0) for m in TOKEN.finditer(text) if m.group(1) not in have]


def main() -> int:
    have = canonical_numbers()
    # List all tracked and staged text files
    cmd = [
        "git",
        "ls-files",
        "*.md",
        "*.nft",
        "*.conf",
        "*.json",
        "*.service",
        "*.sh",
    ]
    res = subprocess.run(cmd, capture_output=True, text=True)
    files = res.stdout.split()
    failures: list[str] = []

    for path in files:
        try:
            with open(path, encoding="utf-8", errors="replace") as f:
                lines = f.read().split("\n")
        except FileNotFoundError:
            continue

        in_fence = False
        for number, line in enumerate(lines, 1):
            if path.endswith(".md"):
                if FENCE.match(line):
                    in_fence = not in_fence
                    continue
                if in_fence:
                    continue

            dead = dead_tokens(line, have)
            if dead:
                failures.append(f"{path}:{number}: {line.strip()[:110]}")

    if not failures:
        print(f"ADR lineage: clean ({len(have)} canonical ADRs, no dangling citations)")
        return 0

    print(f"ADR lineage: {len(failures)} dangling citation(s) — a reference must resolve")
    print(f"to an active file in {ADR_DIR}/ (docs/dev/standards/adr.md).\n")
    for failure in failures:
        print("  " + failure)
    return 1


if __name__ == "__main__":
    sys.exit(main())
