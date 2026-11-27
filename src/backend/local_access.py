"""Loopback bootstrap identity shared by local HTTP services."""

from ipaddress import ip_address


def local_role(peer, headers, port):
    if not ip_address(peer).is_loopback:
        return None
    hosts = headers.get_all("Host", [])
    if len(hosts) != 1 or hosts[0] not in {f"localhost:{port}", f"127.0.0.1:{port}"}:
        return None
    origins = headers.get_all("Origin", [])
    if origins and origins != [f"http://{hosts[0]}"]:
        return None
    if "cross-site" in headers.get_all("Sec-Fetch-Site", []):
        return None
    if "Authorization" in headers or "Proxy-Authorization" in headers:
        return None
    if any(h.lower().startswith(("forwarded", "x-forwarded-", "x-fios-", "x-role",
                                 "x-real-ip", "x-remote-user")) for h in headers):
        return None
    return "admin"
