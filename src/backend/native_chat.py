"""Private Mini worker transport. The native service owns the socket."""

import json
import socket
import sqlite3
import time

from .chat_dispatch import OPERATIONS
from .enrollment import Rejected
from .heartbeat import json_object
from .job_protocol import local
from .wire import read_until, timeout

FRAME_LIMIT = 4096


def local_handler(scheduler, verify_peer):
    def handle(conn, _peer, deadline):
        try:
            verify_peer(conn)
            raw, trailing = read_until(conn, b"\n", FRAME_LIMIT, deadline)
            request = json_object(raw)
            if trailing or request.keys() != {"op", "data"} or not isinstance(request["data"], dict):
                raise Rejected("invalid")
            operation, data = request["op"], request["data"]
            if not isinstance(operation, str):
                raise Rejected("invalid")
            if operation in OPERATIONS:
                session = data.pop("session", None)
                deadline = time.monotonic() + 12
                result = scheduler.dispatch.handle(operation, "fios-core", session, data,
                                                   authorize_peer=lambda: verify_peer(conn))
            else:
                result = local(scheduler, operation, data)
            response = {"ok": True, **result}
        except Rejected as error:
            response = {"ok": False, "reason": error.reason}
        except (ValueError, RecursionError):
            response = {"ok": False, "reason": "invalid"}
        except sqlite3.Error:
            response = {"ok": False, "reason": "store"}
        body = json.dumps(response, allow_nan=False).encode("ascii") + b"\n"
        if len(body) > FRAME_LIMIT:
            raise Rejected("size", 413)
        timeout(conn, deadline)
        conn.sendall(body)
    return handle


def worker_call(path, operation, data, verify_peer):
    body = json.dumps({"op": operation, "data": data}, allow_nan=False).encode("ascii") + b"\n"
    if len(body) > FRAME_LIMIT:
        raise Rejected("size", 413)
    end = time.monotonic() + (13 if operation in OPERATIONS else 3)
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as conn:
        timeout(conn, end)
        conn.connect(str(path))
        verify_peer(conn)
        timeout(conn, end)
        conn.sendall(body)
        raw, trailing = read_until(conn, b"\n", FRAME_LIMIT, end)
        result = json_object(raw)
    if trailing:
        raise Rejected("invalid")
    if result.pop("ok", None) is not True:
        raise Rejected(result.get("reason", "unavailable"), 409)
    return result


def browser_handler(scheduler, secret, inventory=None, *, rehearsal=False):
    from hmac import compare_digest
    import re

    from .chat_bridge import REQUEST_LIMIT
    from .heartbeat import read_request, reply
    from .job_ledger import identifier
    from .job_protocol import OWNER
    from .model_catalog import ALIASES, LARGE_ALIAS
    from .wire import read_exact

    store = scheduler.dispatch.conversations
    owner = "local-moe-rehearsal" if rehearsal else OWNER

    def action_result(action, data):
        fields = {
            "catalog": (), "pair-status": (), "history": ("before",), "conversation": ("id",),
            "create": ("key",), "delete": ("id",), "stop": ("job",),
            "stream": ("id", "job", "ticket"),
            "submit": ("id", "incarnation", "key", "parent", "alias", "prompt", "inventory"),
        }
        if not isinstance(action, str) or action not in fields or data.keys() != set(fields[action]):
            raise Rejected("invalid")
        if action == "pair-status":
            return scheduler.pair_status()
        with scheduler.enrollment.lock, scheduler.jobs.transaction(write=False) as db:
            if rehearsal:
                profiles = dict.fromkeys(ALIASES)
                profiles[LARGE_ALIAS] = scheduler.catalog.rehearsal_profile(db)
            else:
                profiles = {alias: scheduler.catalog.active(db, alias) for alias in ALIASES}
            policies = {item["policy"] for item in profiles.values() if item}
            policy = scheduler.dispatch.policy_revision
            if policy is None and len(policies) == 1:
                policy = next(iter(policies))
            if action == "catalog":
                aliases = {}
                for alias, item in profiles.items():
                    revision = item["revision"] if item else None
                    reason = "unqualified"
                    available = item is not None and item["policy"] == policy
                    if available:
                        intent = dict(resource_class="inference", alias=alias, profile=revision,
                                      tokens=item["output"])
                        if rehearsal:
                            intent["rehearsal"] = item["rehearsal"]
                        if scheduler.eligible(db, intent):
                            reason = "ready"
                        elif scheduler.eligible(db, intent, check_holds=False):
                            reason = "occupied"
                        else:
                            reason = "waiting_capacity"
                    aliases[alias] = dict(available=available, revision=revision, reason=reason)
                return {"incarnation": scheduler.jobs.incarnation(db), "aliases": aliases}
        if action == "history":
            return store.history(owner, policy, data["before"])
        if action == "conversation":
            return store.read(owner, data["id"], policy)
        if action == "stream":
            scheduler.sweep()
            ticket = data["ticket"]
            if ticket is not None:
                identifier(ticket)
            return {"ticket": store.touch_attachment(owner, data["id"], data["job"], ticket)}
        if action == "create":
            return {"id": store.create(owner, data["key"])}
        if action == "delete":
            store.delete(owner, data["id"])
            return {}
        if action == "stop":
            state = scheduler.cancel(owner, identifier(data["job"]))
            return {"state": state["state"]}
        if type(data["inventory"]) is not bool:
            raise Rejected("invalid")
        context = None
        if data["inventory"] and inventory is not None:
            context = json.dumps(inventory(), allow_nan=False, separators=(",", ":"))
        return store.submit(owner, data["id"], data["incarnation"], data["key"], data["parent"],
                            data["alias"], data["prompt"], data["inventory"], inventory_context=context,
                            browser=True, rehearsal=rehearsal)

    expected = "Bearer " + secret.hex()

    def handle(connection, _peer, deadline):
        try:
            method, target, headers, remainder = read_request(connection, deadline)
            if method != "POST" or target != "/v1/chat":
                raise Rejected("route", 404)
            auth = headers.get_all("Authorization", [])
            if len(auth) != 1 or not compare_digest(auth[0], expected):
                raise Rejected("identity", 403)
            sizes = headers.get_all("Content-Length", [])
            if (len(sizes) != 1 or not re.fullmatch(r"[0-9]{1,8}", sizes[0])
                    or "Transfer-Encoding" in headers
                    or headers.get_all("Content-Type", []) != ["application/json"]):
                raise Rejected("framing")
            size = int(sizes[0])
            if size > REQUEST_LIMIT:
                raise Rejected("size", 413)
            request = json_object(read_exact(connection, remainder, size, deadline))
            if request.keys() != {"action", "data"} or not isinstance(request["data"], dict):
                raise Rejected("invalid")
            reply(connection, deadline, 200, action_result(request["action"], request["data"]))
        except Rejected as error:
            reply(connection, deadline, error.status, {"reason": error.reason})
        except (ValueError, RecursionError):
            reply(connection, deadline, 400, {"reason": "invalid"})
        except sqlite3.Error:
            reply(connection, deadline, 503, {"reason": "store"})
    return handle
