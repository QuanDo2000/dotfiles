#!/usr/bin/env python3
"""Interactively provision Lix/Nix package credentials, outside the Nix store."""
import base64
import getpass
import netrc
import os
from pathlib import Path
import stat
import sys
import tempfile
import urllib.error
import urllib.request
import urllib.parse
import warnings

HOST = "pkgs.superlogical.com"
URL = f"https://{HOST}/rex/nix/snapshot.tar.gz"
LIMIT = 1024 * 1024


def save_token(path, token):
    """Append one validated machine entry without changing other credentials."""
    original = b""
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except FileNotFoundError:
        pass
    else:
        with os.fdopen(fd, "rb") as source:
            metadata = os.fstat(source.fileno())
            if not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != os.geteuid():
                raise ValueError("Refusing non-regular or foreign-owned netrc")
            original = source.read(LIMIT + 1)
            if len(original) > LIMIT:
                raise ValueError("netrc exceeds 1 MiB; manual setup required")
        credentials = netrc.netrc(path)
        if HOST in credentials.hosts:
            raise ValueError("Rex already has an entry; use sudoedit /etc/nix/netrc to rotate it")
    if not token or not token.isascii() or any(c.isspace() or ord(c) < 33 or ord(c) > 126 for c in token) or any(c in token for c in '\"\\#'):
        raise ValueError("Token must be nonempty printable ASCII without whitespace, quotes, backslashes or #")
    entry = f"\nmachine {HOST}\n  login rex\n  password {token}\n".encode()
    fd, temporary = tempfile.mkstemp(prefix=".rex-netrc-", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as output:
            output.write(original + entry)
            output.flush()
            os.fsync(output.fileno())
        netrc.netrc(temporary)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def main():
    if os.geteuid() != 0:
        raise SystemExit("Run through dotfile rex-auth (requires sudo).")
    if not os.isatty(0):
        raise SystemExit("Run in an interactive terminal; token input is never accepted from a pipe.")
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("error", getpass.GetPassWarning)
            token = getpass.getpass("Rex package token (hidden): ")
    except getpass.GetPassWarning:
        raise SystemExit("Hidden input is unavailable; use an attended terminal.") from None
    # Upstream can redirect authenticated requests to a signed download URL.
    # Follow only HTTPS, without carrying the package token to the next hop.
    class DownloadRedirect(urllib.request.HTTPRedirectHandler):
        max_redirections = 4
        max_repeats = 2

        def redirect_request(self, req, fp, code, msg, headers, newurl):
            destination = urllib.parse.urlsplit(newurl)
            if destination.scheme != "https" or not destination.hostname or destination.username is not None or destination.password is not None:
                raise ValueError("Unsafe package redirect; credentials not saved")
            return urllib.request.Request(newurl, method="HEAD")
    authorization = base64.b64encode(f"rex:{token}".encode()).decode()
    request = urllib.request.Request(URL, headers={"Authorization": f"Basic {authorization}"}, method="HEAD")
    try:
        with urllib.request.build_opener(DownloadRedirect).open(request, timeout=30) as response:
            if response.status != 200:
                raise ValueError("Unexpected package server response; credentials not saved")
        save_token(Path("/etc/nix/netrc"), token)
    except urllib.error.HTTPError as error:
        raise SystemExit(f"Package server returned HTTP {error.code}; credentials not saved") from None
    except (OSError, ValueError, netrc.NetrcParseError):
        # Parser errors can include credential-bearing lines; never print them.
        raise SystemExit("Could not validate or save credentials. Check access and existing netrc entries; existing data was preserved.") from None
    print("Token validated and saved in /etc/nix/netrc (root-only, 0600).")


def credential_ready():
    path = Path("/etc/nix/netrc")
    try:
        metadata = path.lstat()
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != 0 or stat.S_IMODE(metadata.st_mode) != 0o600 or metadata.st_size > LIMIT:
            return False
        entry = netrc.netrc(path).authenticators(HOST)
        return entry is not None and entry[0] == "rex" and bool(entry[2])
    except (OSError, netrc.NetrcParseError):
        return False


if __name__ == "__main__":
    if sys.argv[1:] == ["--check"]:
        raise SystemExit(0 if os.geteuid() == 0 and credential_ready() else 1)
    if sys.argv[1:]:
        raise SystemExit("Usage: rex_auth.py [--check]")
    try:
        main()
    except (KeyboardInterrupt, EOFError):
        raise SystemExit("Token setup cancelled; credentials not saved.") from None
