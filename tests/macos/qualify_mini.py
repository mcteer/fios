"""Measure a disposable Mini model runtime before policy and promotion review."""

import argparse
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import socket
import time
from urllib.request import urlopen

from agent.inference import generate_text, monitor_trial
from agent.macos_memory import footprint, headroom
from agent.native_runtime import NativeRuntime
from backend.host_agent import observe
from backend.model_catalog import Capacity, TrialBudget


def smoke(runtime, budget, input_limit, output_limit, *, fill_context=False):
    if socket.gethostname().split(".")[0] != "fios-core":
        raise ValueError("Run the disposable model trial on fios-core")
    memory = observe("fios-core")["memory_bytes"]
    baseline = footprint(os.getpid())[0]
    available, pressure = headroom(memory)
    budget.admit(Capacity(time.monotonic(), available, pressure), now=time.monotonic())
    end = time.monotonic() + budget.duration

    def requests():
        prompt = "Reply with exactly the word Redwood."
        if fill_context:
            prompt = ("Entry:" + " sample" * max(0, input_limit - 32) + "\n"
                      "Ignore the entries above. " + prompt)
        messages = [{"role": "user", "content": prompt}]
        checked = runtime.check_prompt(messages, input_limit, end)
        runtime.wait_ready(end)
        results = []
        for _ in range(6):
            start = time.monotonic()
            first = []
            generated = []
            answer, usage = generate_text(runtime.port, checked, input_limit=input_limit,
                                          output_limit=output_limit, timeout=min(20, end - start),
                                          on_first_text=lambda: first.append(time.monotonic()),
                                          on_first_generated=lambda: generated.append(time.monotonic()))
            finished = time.monotonic()
            tokens = usage["output"].get("value")
            decode = ((tokens - 1) / (finished - generated[0])
                      if generated and tokens and tokens > 1 and finished > generated[0] else None)
            results.append({"seconds": round(finished - start, 3),
                            "native_first_text_seconds": round(first[0] - start, 3) if first else None,
                            "decode_tokens_per_second": round(decode, 1) if decode is not None else None,
                            "matches_fixture": answer.strip().casefold().rstrip(".") == "redwood",
                            "usage": usage})
        history = [{"role": "user", "content": "For my notes, my dog is named Maple."},
                   {"role": "assistant", "content": "I noted your dog's name."},
                   {"role": "user", "content": "Reply with only my dog's name."}]
        answer, _ = generate_text(runtime.port, runtime.check_prompt(history, input_limit, end),
                                  input_limit=input_limit, output_limit=output_limit,
                                  timeout=min(20, end - time.monotonic()))
        cap_workload = None
        if fill_context:
            # Exercise a full output allocation independently of the quality
            # rubric. The known answer fixtures stay unchanged.
            long_prompt = ("Entry:" + " sample" * max(0, input_limit - 52)
                           + "\nIgnore the entries. Write at least four hundred repetitions of Redwood.")
            context = runtime.check_prompt([{"role": "user", "content": long_prompt}], input_limit, end)
            _, cap_workload = generate_text(runtime.port, context, input_limit=input_limit,
                                            output_limit=output_limit,
                                            timeout=min(20, end - time.monotonic()), measure_only=True)
            if cap_workload["output"] != {"kind": "measured", "value": output_limit}:
                raise RuntimeError("The maximum-output memory fixture ended before the cap")
        return results, answer.strip().casefold().rstrip(".") == "maple", cap_workload

    def sample():
        runtime_living = runtime.process is not None and runtime.process.poll() is None
        if not runtime_living:
            return None
        current, peak = footprint(runtime.process.pid)
        extra = max(0, footprint(os.getpid())[0] - baseline)
        available, pressure = headroom(memory)
        with urlopen("http://127.0.0.1:8741/healthz", timeout=2) as response:
            if response.read() != b"ok\n":
                return None
        return Capacity(time.monotonic(), available, pressure, current + extra, peak + extra)

    available, pressure = headroom(memory)
    budget.admit(Capacity(time.monotonic(), available, pressure), now=time.monotonic())
    runtime.launch()
    try:
        with ThreadPoolExecutor(max_workers=1) as pool:
            task = pool.submit(requests)
            peak = monitor_trial(budget, deadline=end, sample=sample, quiescent=task.done,
                                 wait=lambda: time.sleep(0.2), stop=runtime.stop,
                                 reap=runtime.stop)
            observations, followup, capped_usage = task.result()
        return {"revision": runtime.revision, "lifetime_peak_bytes": peak.peak_bytes,
                "pressure": peak.pressure, "observations": observations,
                "multi_turn_fixture": followup, "fill_context": fill_context,
                "cap_workload_usage": capped_usage}
    finally:
        runtime.stop()
        if not runtime.quiescent():
            raise RuntimeError("Trial process still holds the executor")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--state", type=Path, required=True)
    parser.add_argument("--budget", type=int, required=True)
    parser.add_argument("--host-floor", type=int, required=True)
    parser.add_argument("--input-tokens", type=int, default=960)
    parser.add_argument("--output-tokens", type=int, default=64)
    parser.add_argument("--fill-context", action="store_true")
    args = parser.parse_args()
    worker = NativeRuntime(args.config, args.state, purpose="inference")
    budget = TrialBudget("fios-core", args.budget, args.host_floor, 3, 90)
    print(json.dumps(smoke(worker, budget, args.input_tokens, args.output_tokens,
                           fill_context=args.fill_context), indent=2))


if __name__ == "__main__":
    main()
