"""Native runtime lifecycle guards."""

from http.client import HTTPConnection, HTTPException
import json
import re
import socket
from threading import Timer
import time

from backend.enrollment import Rejected
from backend.job_ledger import integer, usage_counts


def monitor_trial(budget, *, deadline, sample, quiescent, wait, stop, reap, clock=time.monotonic):
    """Monitor outside inference. The caller owns the exclusive reservation.

    The callbacks must have bounded deadlines. Reap must confirm quiescence,
    raising on failure so the caller can retain its cleanup hold.
    """
    try:
        while True:
            finished = quiescent()
            capacity = sample()
            now = clock()
            if now >= deadline:
                raise Rejected("trial_deadline", 409)
            budget.check(capacity, now=now, completed=finished)
            if finished:
                return capacity
            wait()
    except BaseException:
        try:
            stop()
        finally:
            reap()
        raise


def read_completion(stream, *, input_limit, output_limit, deadline=None, clock=time.monotonic,
                    on_first_text=None, on_first_generated=None, measure_only=False):
    """Read bounded single-choice SSE into a private full-answer buffer.

    The transport must also enforce a socket read deadline. Return only after
    stop/length and the terminal sentinel. Usage is optional and independent.
    """
    frame_limit = 16 * 1024
    answer_limit = 64 * 1024
    stream_limit = 2 * 1024 * 1024
    total = 0
    answer = bytearray()
    counts = {}
    finished = False
    first_generated = False
    while total < stream_limit:
        if deadline is not None and clock() >= deadline:
            raise Rejected("runtime_deadline", 504)
        line = stream.readline(frame_limit + 1)
        total += len(line)
        if not line or len(line) > frame_limit or total > stream_limit or not line.endswith(b"\n"):
            break
        line = line.rstrip(b"\r\n")
        if not line or line.startswith(b":"):
            continue
        if not line.startswith(b"data:"):
            break
        payload = line[5:].lstrip(b" ")
        if payload == b"[DONE]":
            # Qualification can measure a full decode budget without treating
            # a reasoning-only run as a publishable answer.
            if finished and (answer or (measure_only and first_generated)):
                text = answer.decode()
                if re.search(r"</?(?:think|reasoning)>", text, re.IGNORECASE):
                    raise Rejected("runtime_reasoning_channel", 502)
                return text, usage_counts(counts, output_limit, input_limit=input_limit)
            break
        try:
            message = json.loads(payload)
            choices = message["choices"]
            if not isinstance(choices, list):
                break
            reported = message.get("usage")
            if reported is not None:
                if not isinstance(reported, dict) or counts:
                    break
                counts.update({
                    direction: {"kind": "measured", "value": reported[name]}
                    for direction, name in (("input", "prompt_tokens"), ("output", "completion_tokens"))
                    if name in reported
                })
            if not choices and reported is not None:
                continue
            if len(choices) != 1 or finished:
                break
            choice = choices[0]
            delta = choice["delta"]
            if not isinstance(delta, dict) or delta.keys() - {
                    "content", "role", "reasoning_content", "reasoning", "tool_calls", "function_call",
                    "tool_call_id", "name"}:
                break
            # MLX-VLM serializes unset tool metadata as explicit nulls.
            if (delta.get("tool_calls") or delta.get("function_call")
                    or delta.get("tool_call_id") is not None or delta.get("name") is not None):
                break
            text = delta.get("content")
            channels = (text, delta.get("reasoning"), delta.get("reasoning_content"))
            if not first_generated and any(isinstance(item, str) and item for item in channels):
                first_generated = True
                if on_first_generated is not None:
                    on_first_generated()
            if text is not None:
                if not isinstance(text, str):
                    break
                if text and not answer and on_first_text is not None:
                    on_first_text()
                answer.extend(text.encode())
                if len(answer) > answer_limit:
                    break
            reason = choice.get("finish_reason")
            if reason is not None:
                if reason not in ("stop", "length"):
                    break
                finished = True
        except (ValueError, TypeError, AttributeError, KeyError, RecursionError):
            break
    raise Rejected("runtime_stream_invalid", 502)


def generate_text(port, messages, *, input_limit, output_limit, timeout, on_first_text=None,
                  temperature=0, local_model=None, on_first_generated=None, measure_only=False):
    """Call only the worker's preconfigured loopback endpoint.

    The caller must tokenize the pinned template and hold a current grant before
    using this adapter. A network timeout does not certify process quiescence.
    """
    integer(port, 1, 65535)
    integer(input_limit, 1, 1_000_000)
    integer(output_limit, 1, 1_000_000)
    if (not isinstance(messages, list) or not 1 <= len(messages) <= 128
            or type(timeout) not in (int, float) or not 0 < timeout <= 3600
            or type(temperature) not in (int, float) or not 0 <= temperature <= 2):
        raise Rejected("invalid")
    for message in messages:
        if (not isinstance(message, dict) or message.keys() != {"role", "content"}
                or message["role"] not in ("system", "user", "assistant")
                or not isinstance(message["content"], str)
                or len(message["content"]) > 64 * 1024):
            raise Rejected("invalid")
    request = dict(messages=messages, max_tokens=output_limit, stream=True, temperature=temperature,
                   stream_options={"include_usage": True})
    if local_model is not None:
        # MLX-VLM requires its model field. The worker supplies only the
        # independently verified local directory from native configuration.
        if not isinstance(local_model, str) or not local_model.startswith("/"):
            raise Rejected("invalid")
        request["model"] = local_model
    body = json.dumps(request).encode("ascii")
    if len(body) > 256 * 1024:
        raise Rejected("too_large", 413)
    deadline = time.monotonic() + timeout
    client = HTTPConnection("127.0.0.1", port, timeout=timeout)
    timer = None
    try:
        client.connect()
        connection = client.sock

        def interrupt():
            # Shut down the captured socket even if HTTPConnection has handed it
            # off to the response reader. This also bounds a trickled header.
            try:
                connection.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass

        timer = Timer(max(0, deadline - time.monotonic()), interrupt)
        timer.start()
        client.request("POST", "/v1/chat/completions", body,
                       {"Content-Type": "application/json", "Accept": "text/event-stream"})
        with client.getresponse() as response:
            media = (response.getheader("Content-Type") or "").split(";", 1)[0].strip()
            if response.status != 200 or media != "text/event-stream":
                raise Rejected("runtime_unavailable", 502)
            return read_completion(response, input_limit=input_limit, output_limit=output_limit,
                                   deadline=deadline, on_first_text=on_first_text,
                                   on_first_generated=on_first_generated, measure_only=measure_only)
    except (OSError, HTTPException):
        raise Rejected("runtime_unavailable", 502) from None
    finally:
        if timer is not None:
            timer.cancel()
            timer.join()
        client.close()
