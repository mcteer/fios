"""Installed-package tests: loopback plus private generated guard-fixture Unix sockets only."""
import ipaddress
import os
import stat
import tempfile
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


def check_private_unix(address):
    try:
        path=Path(os.fsdecode(address));parent=path.parent.resolve()
        info=parent.stat();target=path.lstat()
        if (parent.parent!=Path(tempfile.gettempdir()).resolve() or not parent.name.startswith('fg-')
                or path.name!='observe.sock' or info.st_uid!=os.geteuid() or info.st_mode & 0o077
                or not stat.S_ISSOCK(target.st_mode) or target.st_uid!=os.geteuid() or target.st_mode & 0o077):
            raise ValueError()
    except (ValueError,TypeError,OSError):
        raise AssertionError('Only private generated Unix guard fixtures are permitted.') from None


def guarded_connect(self,address):
    if self.family==socket.AF_UNIX:check_private_unix(address)
    else:check(address)
    return connect(self,address)


def guarded_connect_ex(self,address):
    if self.family==socket.AF_UNIX:check_private_unix(address)
    else:check(address)
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
