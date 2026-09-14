#!/usr/bin/env python3
"""Conservative preflight for the lab's Windows Administrator password; stdin only.

This catches common first-boot failures, not custom policy, history or account state.
Never include the supplied password in output or exception messages.
"""
import string
import sys


def valid(password, username="Administrator"):
    categories = (
        any(c in string.ascii_uppercase for c in password),
        any(c in string.ascii_lowercase for c in password),
        any(c in string.digits for c in password),
        any(c in string.punctuation for c in password),
    )
    return (len(password) >= 8 and sum(categories) >= 3
            and not any(c in password for c in '\r\n\x00')
            and (len(username) < 3 or username.casefold() not in password.casefold()))


if __name__ == "__main__":
    if not valid(sys.stdin.read(), sys.argv[1] if len(sys.argv) > 1 else "Administrator"):
        sys.exit("Lab password preflight failed: use at least 8 characters, three of uppercase/lowercase/digits/punctuation, no account name, and no newline or NUL. Update clone-admin-password in secrets/lab.yaml.")
