"""Isolated installed-package unittest runner with a loopback-only socket guard."""
import ipaddress
from pathlib import Path
import socket
import sys
import unittest


def loopback(address):
    if isinstance(address,bytes):address=address.decode('ascii')
    try:return ipaddress.ip_address(address).is_loopback
    except (TypeError,ValueError):return address=='localhost'


connect=socket.socket.connect
connect_ex=socket.socket.connect_ex
sendto=socket.socket.sendto
getaddrinfo=socket.getaddrinfo


def check(address):
    if not isinstance(address,tuple) or not loopback(address[0]):
        raise AssertionError('Non-loopback network access is forbidden in Python unit tests.')


def guarded_connect(self,address):
    check(address)
    return connect(self,address)


def guarded_connect_ex(self,address):
    check(address)
    return connect_ex(self,address)


def guarded_sendto(self,data,*args):
    check(args[-1])
    return sendto(self,data,*args)


def guarded_getaddrinfo(host,*args,**kwargs):
    if host is not None and not loopback(host):
        raise AssertionError('External DNS is forbidden in Python unit tests.')
    return getaddrinfo(host,*args,**kwargs)


socket.socket.connect=guarded_connect
socket.socket.connect_ex=guarded_connect_ex
socket.socket.sendto=guarded_sendto
socket.getaddrinfo=guarded_getaddrinfo
root=Path(__file__).resolve().parents[2]
suite=unittest.defaultTestLoader.discover(str(root/'tests/agent'),pattern='test_*.py')
result=unittest.TextTestRunner(verbosity=2).run(suite)
sys.exit(0 if result.wasSuccessful() else 1)
