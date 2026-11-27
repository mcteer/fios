"""Private machine TLS and operator-provided leaf verification."""

import hashlib
from ipaddress import IPv4Address, IPv4Network
from pathlib import Path
import re
import ssl
import subprocess

from .enrollment import MACHINE, Rejected, private_path

PRIVATE_NETWORKS = tuple(map(IPv4Network, ("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16")))


def management_address(value, testing=False):
    address = IPv4Address(value)
    if testing and address == IPv4Address("127.0.0.1"):
        return str(address)
    if not any(address in network and address not in (network.network_address,
                                                      network.broadcast_address)
               for network in PRIVATE_NETWORKS):
        raise ValueError("Expected an approved private management IPv4 address")
    return str(address)


def context(ca, cert=None, key=None, *, server=False):
    tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER if server else ssl.PROTOCOL_TLS_CLIENT)
    tls.minimum_version = ssl.TLSVersion.TLSv1_3
    tls.verify_mode = ssl.CERT_REQUIRED
    tls.verify_flags |= ssl.VERIFY_X509_STRICT
    tls.hostname_checks_common_name = False
    tls.options |= ssl.OP_NO_TICKET
    if server:
        tls.num_tickets = 0
    tls.load_verify_locations(cafile=ca)
    if cert is not None:
        private_path(Path(key))
        tls.load_cert_chain(cert, key, password=lambda: "")
    elif server:
        raise ValueError("A server certificate is required")
    return tls


def fingerprint(der):
    return hashlib.sha256(der).hexdigest()


def verified_worker_leaf(openssl, ca, pem, machine):
    if (not isinstance(machine, str) or not MACHINE.fullmatch(machine)
            or not isinstance(pem, str) or not re.fullmatch(
                r"-----BEGIN CERTIFICATE-----\r?\n[A-Za-z0-9+/=\r\n]+-----END CERTIFICATE-----\s*",
                pem, re.ASCII)):
        raise Rejected("invalid")
    encoded = pem.encode("ascii")
    try:
        subprocess.run(
            [openssl, "verify", "-CAfile", ca, "-no-CApath", "-no-CAstore",
             "-purpose", "sslclient", "-x509_strict"],
            input=encoded, capture_output=True, check=True, timeout=2,
        )
        result = subprocess.run(
            [openssl, "x509", "-noout", "-ext",
             "basicConstraints,keyUsage,extendedKeyUsage,subjectAltName"],
            input=encoded, capture_output=True, check=True, timeout=2, text=False,
        ).stdout.decode("ascii")
        fields = {}
        heading = None
        for line in result.splitlines():
            if line.startswith("X509v3 "):
                heading = line.split(":", 1)[0]
            elif heading and line.strip():
                fields[heading] = line.strip()
        if fields != {"X509v3 Basic Constraints": "CA:FALSE",
                      "X509v3 Key Usage": "Digital Signature",
                      "X509v3 Extended Key Usage": "TLS Web Client Authentication",
                      "X509v3 Subject Alternative Name": f"DNS:{machine}"}:
            raise Rejected("invalid-certificate")
        return fingerprint(ssl.PEM_cert_to_DER_cert(pem.strip()))
    except (ValueError, subprocess.SubprocessError, OSError):
        raise Rejected("invalid-certificate") from None
