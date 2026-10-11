#!/usr/bin/env python3
"""Validate PostgreSQL identifier policy in hand-written DDL."""

from __future__ import annotations

import argparse
import re
from pathlib import Path

MAX_BYTES = 63
BUSINESS_MAX_CHARS = 30
BUSINESS_PREFIXES = ("RAT_", "PAY_", "INC_")
PATTERNS = {
    "table": re.compile(r'CREATE\s+TABLE\s+IF\s+NOT\s+EXISTS\s+"([^"]+)"', re.I),
    "materialized_view": re.compile(
        r'CREATE\s+MATERIALIZED\s+VIEW\s+IF\s+NOT\s+EXISTS\s+"([^"]+)"', re.I
    ),
    "index": re.compile(
        r'CREATE\s+(?:UNIQUE\s+)?INDEX\s+IF\s+NOT\s+EXISTS\s+([A-Za-z0-9_]+)',
        re.I,
    ),
    "constraint": re.compile(r'CONSTRAINT\s+([A-Za-z0-9_]+)', re.I),
}


def parse_args() -> argparse.Namespace:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("schema_file", type=Path)
    parser.add_argument(
        "--identifier",
        action="append",
        default=[],
        metavar="KIND:NAME",
        help="Validate an additional proposed identifier",
    )
    return parser.parse_args()


def parse_proposed(value: str) -> tuple[str, str]:
    """Parse a proposed identifier in KIND:NAME form."""
    kind, separator, identifier = value.partition(":")
    if not separator or kind not in PATTERNS or not identifier:
        raise ValueError("expected KIND:NAME with a supported kind")
    return kind, identifier


def collect_identifiers(text: str) -> list[tuple[str, str]]:
    """Collect supported identifier declarations from DDL text."""
    identifiers: list[tuple[str, str]] = []
    for kind, pattern in PATTERNS.items():
        identifiers.extend((kind, match) for match in pattern.findall(text))
    return identifiers


def validate(kind: str, identifier: str) -> list[str]:
    """Return policy violations for one identifier."""
    violations: list[str] = []
    if len(identifier.encode("utf-8")) > MAX_BYTES:
        violations.append(f"{kind} {identifier!r} exceeds {MAX_BYTES} bytes")
    if kind in {"table", "materialized_view"}:
        if len(identifier) > BUSINESS_MAX_CHARS:
            violations.append(
                f"{kind} {identifier!r} exceeds {BUSINESS_MAX_CHARS} characters"
            )
        if not identifier.isascii():
            violations.append(f"{kind} {identifier!r} must use ASCII characters")
        if not identifier.isupper():
            violations.append(f"{kind} {identifier!r} must be uppercase")
        if not identifier.startswith(BUSINESS_PREFIXES):
            violations.append(
                f"{kind} {identifier!r} must start with one of {BUSINESS_PREFIXES}"
            )
    return violations


def main() -> int:
    """Validate the selected DDL file and proposed identifiers."""
    args = parse_args()
    identifiers = collect_identifiers(args.schema_file.read_text(encoding="utf-8"))
    for value in args.identifier:
        try:
            identifiers.append(parse_proposed(value))
        except ValueError as error:
            print(f"ERROR: {value}: {error}")
            return 2
    violations = [
        violation
        for kind, identifier in identifiers
        for violation in validate(kind, identifier)
    ]
    if violations:
        for violation in violations:
            print(f"ERROR: {violation}")
        return 1
    print(f"OK: validated {len(identifiers)} identifiers from {args.schema_file}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
