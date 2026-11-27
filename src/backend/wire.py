"""Bounded framing shared by the native service and local inventory reader."""

import time


class FrameTooLarge(ValueError):
    pass


def timeout(connection, deadline):
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        raise TimeoutError
    connection.settimeout(remaining)


def read_until(connection, delimiter, limit, deadline):
    buff = bytearray()
    while delimiter not in buff:
        if len(buff) >= limit:
            raise FrameTooLarge("Header limit exceeded")
        timeout(connection, deadline)
        chunk = connection.recv(min(2048, limit - len(buff)))
        if not chunk:
            raise ValueError("Incomplete message")
        buff.extend(chunk)
    before, after = bytes(buff).split(delimiter, 1)
    return before, after


def read_exact(connection, data, length, deadline):
    if len(data) > length:
        raise ValueError("Extra bytes")
    while len(data) < length:
        timeout(connection, deadline)
        chunk = connection.recv(length - len(data))
        if not chunk:
            raise ValueError("Incomplete body")
        data += chunk
    return data


def read_reply(connection, deadline, limit):
    head, prefix = read_until(connection, b"\r\n\r\n", 8192, deadline)
    status, *fields = head.split(b"\r\n")
    version, code, _ = status.split(b" ", 2)
    if version != b"HTTP/1.1" or len(code) != 3 or not code.isdigit():
        raise ValueError("Invalid response status")
    lengths = []
    for field in fields:
        key, separator, value = field.partition(b":")
        if not separator or key.lower() == b"transfer-encoding":
            raise ValueError("Invalid response framing")
        if key.lower() == b"content-length":
            lengths.append(value.strip())
    if len(lengths) != 1 or not lengths[0].isdigit() or len(lengths[0]) > 8:
        raise ValueError("Invalid response size")
    length = int(lengths[0])
    if length > limit:
        raise FrameTooLarge("Response limit exceeded")
    return int(code), read_exact(connection, prefix, length, deadline)
