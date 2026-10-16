#!/usr/bin/env python3
"""Parse the explicit trusted GitHub author allowlist for squash auto-merge."""
import re

LOGIN = re.compile(r"^[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?$")


def parse_approved_authors(value):
    """Return case-insensitive exact GitHub logins; reject bad configuration."""
    if not isinstance(value, str):
        raise ValueError("Approved authors must be a string")
    authors = set()
    for name in re.split(r"[,\s]+", value.strip()):
        if not name:
            continue
        if not LOGIN.fullmatch(name):
            raise ValueError("Approved authors contains an invalid login")
        authors.add(name.casefold())
    return authors
