#!/usr/bin/env python3
"""Print the newest Lerd version among the tags passed as arguments.

Stable beats a prerelease of the same core version (1.37.1 > 1.37.1-beta.2,
1.37.0 > 1.37.0-beta.10). A later core version wins either way
(1.38.0-beta.1 > 1.37.1). GNU sort -V gets the first of those wrong, which
is why this is not `sort -V`.

The first argument is the stable release and must parse. Later arguments are
prerelease tags; ones that are not dotted semver are ignored.
"""

import re
import sys

_VERSION = re.compile(r"v?(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?$")


def parse(raw):
    match = _VERSION.fullmatch(raw.strip())
    if match is None:
        return None
    pre = match.group(4)
    parts = ()
    if pre is not None:
        parts = tuple((0, int(part)) if part.isdigit() else (1, part) for part in pre.split("."))
    # The boolean is True for a stable release, so it sorts after any
    # prerelease with the same major.minor.patch.
    return (int(match.group(1)), int(match.group(2)), int(match.group(3)), pre is None, parts)


def bare(raw):
    return raw[1:] if raw.startswith("v") else raw


def main(argv):
    if len(argv) < 2 or not argv[1].strip():
        print("usage: newest-lerd-version.py <stable-tag> [prerelease-tag ...]", file=sys.stderr)
        return 1

    stable = parse(argv[1])
    if stable is None:
        print(f"unrecognized stable version: {argv[1]}", file=sys.stderr)
        return 1

    candidates = [(argv[1], stable)]
    for raw in argv[2:]:
        if not raw.strip():
            continue
        parsed = parse(raw)
        if parsed is None:
            print(f"ignoring unrecognized release {raw}", file=sys.stderr)
            continue
        candidates.append((raw, parsed))

    winner = max(candidates, key=lambda item: item[1])
    print(bare(winner[0]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
