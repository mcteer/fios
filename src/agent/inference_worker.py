"""Execute one lease at a time and require verified runtime cleanup."""

import base64
from concurrent.futures import ThreadPoolExecutor
import json
from subprocess import SubprocessError
import time

from backend.chat_dispatch import PAGE
from backend.enrollment import Rejected


class InferenceWorker:
    """The transport supplies identity. The host runtime owns its process state."""

    def __init__(self, control, transfer, describe_capacity, runtime, *, paired_runtime=None,
                 clock=time.monotonic, stopping=lambda: False):
        self.control = control
        self.transfer = transfer
        self.describe_capacity = describe_capacity
        self.runtime = runtime
        self.paired_runtime = paired_runtime
        self.clock = clock
        self.stopping = stopping
        self.resident = None
        self.prepared = None

    def report(self):
        if self.paired_runtime:
            self.paired_runtime.check_budget()
        return self.control("capacity", self.describe_capacity(self.resident))

    def reconcile(self, offer):
        runtimes = [runtime for runtime in (self.runtime, self.paired_runtime) if runtime is not None]
        for runtime in runtimes:
            runtime.stop()
        if any(not runtime.quiescent() for runtime in runtimes):
            raise Rejected("cleanup_required", 409)
        self.resident = None
        sample = self.describe_capacity(None)
        self.control("capacity", sample)
        self.control("cleaned", {"challenge": offer["challenge"], "sequence": sample["sequence"],
                                 "disposition": "quiescent"})

    def step(self):
        self.report()
        sent = self.clock()
        offer = self.control("poll", {})
        action = offer["action"]
        if action in ("stop", "unload"):
            self.prepared = None
            self.reconcile(offer)
            return
        if action == "prepare":
            grant = {key: offer[key] for key in ("epoch", "job", "generation", "grant")}
            if "trial" in offer or "pair" in offer:
                if not self.paired_runtime:
                    raise Rejected("profile_unavailable", 409)
                self.paired_runtime.prepare(offer)
            elif self.runtime is None:
                raise Rejected("profile_unavailable", 409)
            self.control("ready", grant)
            self.prepared = grant
            sent = self.clock()
            offer = self.control("poll", {})
            action = offer["action"]
        if action != "start":
            if action != "prepare":
                self.prepared = None
            return
        # Only the process which acknowledged preparation can honor a start.
        grant, self.prepared = self.prepared, None
        if not grant or any(offer.get(key) != value for key, value in grant.items()):
            return
        transit = self.clock() - sent
        start = {**offer, "remaining": offer["remaining"] - transit}
        if "job_remaining" in start:
            start["job_remaining"] -= transit
        try:
            self.execute(start, grant)
        except (OSError, ValueError, TimeoutError, SubprocessError) as error:
            runtime = self.execution_runtime(start)
            runtime.stop()
            result = ("withheld" if isinstance(error, Rejected)
                      and error.reason == "publication_withheld" else "failed")
            try:
                details = {}
                if isinstance(error, Rejected) and ("pair" in start or "trial" in start):
                    if error.reason == "transport_unavailable":
                        details["failure"] = error.reason
                    elif (error.reason in ("unsafe_rank_resources", "stale_rank_resources")
                          and getattr(runtime, "large_stage", None)):
                        details["failure"] = "unsafe_rank_resources"
                    elif error.reason == "context_limit" and start.get("trial", {}).get("placement"):
                        details["failure"] = error.reason
                self.control("finish", {**grant, "result": result, **details})
            except (OSError, ValueError):
                # The next poll and cleanup challenge handle lost sessions.
                pass

    def messages(self, grant):
        cursor = 0
        data = bytearray()
        limits = None
        while cursor is not None:
            page = self.transfer("prompt", {**grant, "cursor": cursor})
            data.extend(base64.b64decode(page["data"], validate=True))
            if len(data) > 80 * 1024:
                raise Rejected("too_large", 413)
            incoming = page["input_limit"], page["output_limit"]
            if limits is not None and limits != incoming:
                raise Rejected("profile_changed", 409)
            limits = incoming
            next_cursor = page["cursor"]
            if next_cursor is not None and next_cursor != len(data):
                raise Rejected("invalid")
            cursor = next_cursor
        return json.loads(data), limits

    def execution_runtime(self, start):
        if "trial" in start or "pair" in start:
            if self.paired_runtime is None:
                raise Rejected("profile_unavailable", 409)
            return self.paired_runtime
        if self.runtime is None:
            raise Rejected("profile_unavailable", 409)
        return self.runtime

    def execute(self, start, grant):
        runtime = self.execution_runtime(start)
        # Start the lease countdown before fetching any content or loading weights.
        now = self.clock()
        deadline = now + start["remaining"]
        job_deadline = now + start.get("job_remaining", start["remaining"])
        if deadline <= self.clock():
            raise Rejected("fenced", 409)
        arm = getattr(runtime, "arm", None)
        if arm is not None:
            arm()
        check_link = getattr(runtime, "check_link", None)
        next_renewal = now + 4
        with ThreadPoolExecutor(max_workers=1) as pool:
            task = pool.submit(self.generate, start, grant, job_deadline)
            try:
                while not task.done():
                    if self.stopping() or self.clock() >= deadline:
                        raise Rejected("fenced", 409)
                    try:
                        task.result(timeout=min(1 if check_link else 4, max(0, deadline - self.clock())))
                    except TimeoutError:
                        if task.done():
                            task.result()
                        if self.stopping() or self.clock() >= deadline:
                            raise Rejected("fenced", 409)
                        if check_link:
                            check_link()
                        if getattr(runtime, "large_stage", None):
                            runtime.check_budget()
                        if self.clock() >= next_renewal:
                            self.report()
                            sent = self.clock()
                            renewed = self.control("renew", grant)
                            deadline = sent + renewed["remaining"]
                            next_renewal = sent + 4
                answer, usage, diagnostics = task.result()
                if check_link:
                    check_link()
            except BaseException as error:
                if check_link and getattr(runtime, "large_stage", None) and isinstance(error, Exception):
                    lost_link = isinstance(error, Rejected) and error.reason == "transport_unavailable"
                    if not lost_link:
                        try:
                            check_link()
                        except Rejected as link_error:
                            lost_link = link_error.reason == "transport_unavailable"
                    if lost_link:
                        try:
                            # A failed receipt fences the pair before reaping.
                            # Each Studio still has to prove its own cleanup.
                            self.control("finish", {**grant, "result": "failed",
                                                    "failure": "transport_unavailable"})
                        except (OSError, ValueError):
                            pass
                        else:
                            runtime.stop()
                            return
                runtime.stop()
                raise
        # End model residency before invoking publication policy, particularly
        # on the Mini where two model footprints can exceed the qualified cap.
        runtime.stop()
        if not runtime.quiescent():
            raise Rejected("cleanup_required", 409)
        if self.stopping():
            raise Rejected("fenced", 409)
        if "trial" in start or ("pair" in start and not start["reporter"]):
            if "review" in start.get("trial", {}) and start["reporter"]:
                from hashlib import sha256

                text = answer.encode()
                if not 0 < len(text) <= 64 * 1024:
                    raise Rejected("invalid_review_output")
                self.report()
                self.control("renew", grant)
                frames = 0
                sent = self.clock()
                for offset in range(0, len(text), PAGE):
                    if self.clock() - sent >= 4:
                        self.report()
                        self.control("renew", grant)
                        sent = self.clock()
                    self.control("review-append", {
                        **grant, "sequence": frames, "data": base64.b64encode(text[offset:offset + PAGE]).decode()})
                    frames += 1
                diagnostics["review_output"] = dict(frames=frames, digest=sha256(text).hexdigest())
            self.control("finish", {**grant, "result": "ok", **diagnostics})
            return
        data = answer.encode()
        frames = 0
        for offset in range(0, len(data), PAGE):
            encoded = base64.b64encode(data[offset:offset + PAGE]).decode()
            self.transfer("append", {**grant, "sequence": frames, "data": encoded})
            frames += 1
        self.report()
        self.control("renew", grant)
        if getattr(runtime, "large_stage", None):
            with ThreadPoolExecutor(max_workers=1) as pool:
                publication = pool.submit(self.transfer, "publish", {**grant, "frames": frames})
                while not publication.done():
                    try:
                        publication.result(timeout=3)
                    except TimeoutError:
                        if publication.done():
                            publication.result()
                        if self.stopping():
                            raise Rejected("fenced", 409)
                        self.report()
                        self.control("renew", grant)
                publication.result()
        else:
            self.transfer("publish", {**grant, "frames": frames})
        self.control("finish", {**grant, "result": "ok", "usage": usage, **diagnostics})

    def generate(self, start, grant, deadline):
        if "trial" in start:
            result = self.paired_runtime.run_trial(start, deadline)
            if "review" in start["trial"]:
                answer, diagnostics = result
                return answer, None, diagnostics
            return None, None, result
        if "pair" in start:
            payload = self.messages(grant) if start["reporter"] else None
            return self.paired_runtime.run_chat(start, payload, deadline)
        messages, (input_limit, output_limit) = self.messages(grant)
        # The runtime validates the exact pinned template and caps. Its stop
        # operation interrupts generation even when the loopback read is blocked.
        answer, usage = self.runtime.generate(start["profile"], messages, input_limit, output_limit, deadline)
        return answer, usage, {}


def run_host(args, observe):
    """Run an explicitly configured native Mini or Studio execution worker."""
    import os
    import signal
    import ssl
    import subprocess
    from threading import Event

    from backend.enroll import peer_uid
    from backend.native_chat import worker_call
    from backend.worker import from_args
    from .macos_memory import headroom
    from .native_runtime import NativeRuntime

    if args.runtime_state is None:
        raise ValueError("Specify a private worker runtime state directory")
    runtime = (NativeRuntime(args.inference_config, args.runtime_state, purpose="inference")
               if args.inference_config else None)
    paired_runtime = None
    if args.pair_config:
        from .paired_runtime import PairedRuntime

        paired_runtime = PairedRuntime(args.pair_config, args.runtime_state, args.node)
    if args.node == "fios-core":
        if args.inference_socket is None or args.remote:
            raise ValueError("Specify the Mini's private inference socket")

        def same_user(connection):
            if peer_uid(connection) != os.geteuid():
                raise Rejected("identity", 403)

        def transport(route, operation, data):
            return worker_call(args.inference_socket, operation, data, same_user)

        reporter = None
    else:
        if args.inference_socket or not args.remote:
            raise ValueError("A Studio worker uses enrolled mutual TLS")
        reporter = from_args(args)

        def transport(route, operation, data):
            request_timeout = 2
            if route == "inference":
                request_timeout = 64 if paired_runtime and paired_runtime.large_stage else 13
            status, body = reporter.request("/v1/" + route + "/" + operation, data,
                                            timeout=request_timeout)
            response = json.loads(body)
            if status != 200:
                raise Rejected(response.get("reason", "transport"), status)
            return response

    stopping = Event()
    signal.signal(signal.SIGTERM, lambda *_: stopping.set())
    signal.signal(signal.SIGINT, lambda *_: stopping.set())
    last_reason = None
    while not stopping.is_set():
        session = None
        sequence = 0
        try:
            if reporter is not None:
                if not reporter.report(observe):
                    raise Rejected("transport", 503)
                session = reporter.session
            else:
                session = transport("jobs", "session", {})["session"]

            def capacity(resident):
                nonlocal sequence
                if reporter is not None and (not reporter.report(observe) or reporter.session != session):
                    raise Rejected("session", 409)
                sample = observe(args.node)
                available, pressure = headroom(sample["memory_bytes"])
                sequence += 1
                result = dict(sequence=sequence, sampled_at=sample["sampled_at"],
                              available_bytes=available, resident_revision=resident,
                              pressure=pressure)
                if reporter is None:
                    result["memory_bytes"] = sample["memory_bytes"]
                if paired_runtime and paired_runtime.large_stage:
                    result["large_revision"] = paired_runtime.revision
                    result["single_capable"] = runtime is not None
                return result

            version = 1
            if paired_runtime:
                version = 3 if paired_runtime.large_stage else 2

            def control(operation, data):
                return transport("jobs", operation, dict(data, version=version, node=args.node, session=session))

            def transfer(operation, data):
                identity = {"session": session} if reporter is None else {
                    "session": session, "version": 1, "node": args.node}
                return transport("inference", operation, {**data, **identity})

            worker = InferenceWorker(control, transfer, capacity, runtime, paired_runtime=paired_runtime,
                                     stopping=stopping.is_set)
            while not stopping.is_set():
                worker.step()
                if last_reason is not None:
                    print("inference worker reporting", flush=True)
                    last_reason = None
                stopping.wait(2)
        except (OSError, ValueError, ssl.SSLError, subprocess.SubprocessError):
            # The next connection needs a fresh session before its capacity
            # sequence resets. Old grants are fenced by that decision.
            if reporter is not None:
                reporter.session = None
            if last_reason is None:
                print("inference worker unavailable", flush=True)
                last_reason = "unavailable"
            stopping.wait(2)
        finally:
            if runtime:
                runtime.stop()
            if paired_runtime:
                paired_runtime.stop()
