import hashlib
import hmac
import http.client
import ipaddress
import os
import secrets
import socket
import ssl
import time
from collections import OrderedDict
from threading import Lock
from urllib.parse import urlsplit

from fastapi import HTTPException


def password_hash(password, salt=None):
    salt = salt or secrets.token_bytes(16)
    value = hashlib.scrypt(password.encode(), salt=salt, n=2**15, r=8, p=1, maxmem=64 * 1024**2)
    return f"{salt.hex()}:{value.hex()}"


DUMMY_HASH = password_hash(secrets.token_hex(32))


def password_matches(password, encoded):
    return hmac.compare_digest(password_hash(password, bytes.fromhex(encoded.split(":")[0])), encoded)


def token_hash(token):
    return hashlib.sha256(token.encode()).hexdigest()


def issue_tokens(tx, user_id, family=None):
    family = family or secrets.token_hex(16)
    result = {"token_type": "bearer", "expires_in": 900}
    for kind, lifetime in (("access", 900), ("refresh", 7 * 86400)):
        token = secrets.token_urlsafe(32)
        tx.run("INSERT INTO tokens VALUES (?,?,?,?,?)",
               (token_hash(token), user_id, kind, int(time.time()) + lifetime, family))
        result[kind + "_token"] = token
    return result


class RateLimit:
    def __init__(self):
        self.entries = OrderedDict()
        self.lock = Lock()

    def check(self, action, ip, limit, seconds):
        now = time.monotonic()
        key = (action, ip)
        with self.lock:
            until, used = self.entries.get(key, (now + seconds, 0))
            if now >= until:
                until, used = now + seconds, 0
            if used >= limit:
                raise HTTPException(429, "Try again later", headers={"Retry-After": str(max(1, int(until - now)))})
            self.entries[key] = (until, used + 1)
            self.entries.move_to_end(key)
            if len(self.entries) > 8192:
                self.entries.popitem(last=False)


def parse_official_url(url, hosts):
    try:
        if any(ord(ch) < 33 or ch in "\\" for ch in url):
            raise ValueError
        target = urlsplit(url)
        if (target.scheme != "https" or target.hostname not in hosts
                or target.username is not None or target.password is not None
                or target.port not in (443, None) or target.fragment
                or not target.path.startswith("/") or target.path.startswith("//")):
            raise ValueError
        return target
    except (TypeError, ValueError):
        raise ValueError("Use an approved HTTPS source URL") from None


NCTB_HOSTS = {"nctb.gov.bd", "www.nctb.gov.bd", "nctb.portal.gov.bd"}


def pdf_hosts():
    return NCTB_HOSTS | {
        host.strip().lower() for host in os.getenv("OFFICIAL_PDF_HOSTS", "").split(",") if host.strip()
    }


class PinnedHTTPSConnection(http.client.HTTPSConnection):
    def __init__(self, hostname, address):
        super().__init__(hostname, timeout=8, context=ssl.create_default_context())
        self.address = address

    def connect(self):
        raw = socket.create_connection((self.address, 443), self.timeout)
        try:
            self.sock = self._context.wrap_socket(raw, server_hostname=self.host)
        except BaseException:
            raw.close()
            raise


def connect_public_https(target):
    addresses = {item[4][0] for item in socket.getaddrinfo(target.hostname, 443, type=socket.SOCK_STREAM)}
    ips = [ipaddress.ip_address(address) for address in addresses]
    if not ips or any(not ip.is_global or ip.is_multicast or getattr(ip, "ipv4_mapped", None) for ip in ips):
        raise ValueError("Source resolved to a disallowed address")
    return PinnedHTTPSConnection(target.hostname, sorted(addresses)[0])


def verify_pdf(url):
    target = parse_official_url(url, pdf_hosts())
    connection = connect_public_https(target)
    try:
        path = target.path + ("?" + target.query if target.query else "")
        connection.request("GET", path, headers={"Range": "bytes=0-15", "Accept-Encoding": "identity"})
        response = connection.getresponse()
        if response.status not in (200, 206) or not response.read(8).startswith(b"%PDF-"):
            raise ValueError("Source did not return a PDF. Redirects require a reviewed direct URL.")
        size = (response.getheader("Content-Range", "").rsplit("/", 1)[-1]
                if response.status == 206 else response.getheader("Content-Length", ""))
        return int(size) if size.isdecimal() and 0 < int(size) < 2**63 else None
    finally:
        connection.close()
