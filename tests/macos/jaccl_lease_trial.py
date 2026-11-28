"""Drive real Studio ranks through the private scheduler using disposable TLS identities."""

from concurrent.futures import ThreadPoolExecutor
from contextlib import ExitStack
from hashlib import sha256
from http.client import HTTPConnection
import json
import os
from pathlib import Path
import re
import shlex
import signal
import socket
import ssl
import subprocess
import sys
import tempfile
from threading import Thread
import time

from backend.chat_bridge import ChatBridge
from backend.chat_dispatch import Dispatch
from backend.conversations import ConversationStore
from backend.core import create_server
from backend.enrollment import Ledger, STUDIOS, elapsed
from backend.heartbeat import Listener, worker_handler
from backend.job_ledger import JobLedger
from backend.job_protocol import TRIAL_OWNER, operator
from backend.machine_tls import context, fingerprint, management_address
from backend.model_catalog import Catalog, Profile
from backend.native_chat import browser_handler
from backend.pair_trial import paired_rdma, transport_observation
from backend.scheduler import Scheduler


def staged_metadata(root, device):
    from agent.native_runtime import digest_file, environment_root, manifest_digest, verify_environment

    model = root / "model"
    engine = root / "venv/bin/python"
    files = {path.name: digest_file(path) for path in model.iterdir() if path.is_file()}
    environment = root / "environment-files.json"
    site = environment_root(engine)
    environment.touch(mode=0o600)
    environment.write_text(json.dumps({path.relative_to(site).as_posix(): digest_file(path)
                                       for path in site.rglob("*") if path.is_file()}))
    executable = digest_file(engine)
    engine_digest = verify_environment(engine, environment, "mlx_lm.server", executable, paired=True)
    raw = subprocess.check_output(["/usr/bin/ibv_devinfo", "-d", device], timeout=3, text=True)
    guid = re.search(r"^\s*node_guid:\s*([0-9a-fA-F:]+)\s*$", raw, re.MULTILINE)
    if guid is None or "PORT_ACTIVE" not in raw or "Thunderbolt" not in raw:
        raise ValueError("Expected the active reviewed RDMA device")
    build = subprocess.check_output(["/usr/bin/sw_vers", "-buildVersion"], timeout=2, text=True).strip()
    identity = f"{device}:{guid[1].replace(':', '').lower()}:{build}"
    return dict(artifact=manifest_digest(files), engine=engine_digest,
                template=files.get("chat_template.jinja", files.get("tokenizer_config.json")),
                device=sha256(identity.encode("ascii")).hexdigest(),
                native=dict(model=str(model), engine=str(engine), executable_sha256=executable,
                            entry="mlx_lm.server", port=1, model_files=files,
                            environment_manifest=str(environment)))


def write_json(path, data):
    path.touch(mode=0o600, exist_ok=False)
    path.write_text(json.dumps(data, ensure_ascii=True))


def worker_config(root, request):
    fixtures = {}
    for name, document in request["fixtures"].items():
        fixture = root / f"approved-fixture-{name}.json"
        write_json(fixture, document)
        fixtures[sha256(fixture.read_bytes()).hexdigest()] = str(fixture)
    write_json(root / "runtime.json", request["runtime"])
    write_json(root / "pair.json", dict(runtime=str(root / "runtime.json"),
                                      devices=["rdma_en5", "rdma_en5"], coordinator="192.168.0.1",
                                      port=request["coordinate_port"], fixtures=fixtures))


def remote_worker(root, args):
    pidfile = root / "trial-worker.pid"
    pidfile.touch(mode=0o600, exist_ok=False)
    pidfile.write_text(str(os.getpid()))
    env = dict(os.environ, PYTHONPATH=str(root / "src"))
    os.execve(sys.executable, [sys.executable, "-B", "-m", "backend.host_agent", *args], env)


def wait_for(check, description, limit=60):
    deadline = time.monotonic() + limit
    while time.monotonic() < deadline:
        value = check()
        if value:
            return value
        time.sleep(0.15)
    raise TimeoutError(description)


def ring_worker(root, request):
    """Negative control for transport verification on a real two-rank TCP run."""
    import mlx.core as mx
    from mlx_lm import stream_generate
    from mlx_lm.sample_utils import make_sampler
    from mlx_lm.utils import sharded_load

    group = mx.distributed.init(backend="ring", strict=True)
    if group.size() != 2 or group.rank() != request["rank"]:
        raise ValueError("Unexpected TCP reference group")
    model, tokenizer = sharded_load(root / "model", tensor_group=group)
    messages = [{"role": "user", "content": request["prompt"]}]
    tokens = tokenizer.apply_chat_template(messages, add_generation_prompt=True)
    operations = 0
    original = mx.distributed.all_sum

    def tracked(array, *, group=None, stream=None):
        nonlocal operations
        result = original(array, group=group, stream=stream)
        mx.eval(result)
        operations += bool(array.nbytes)
        return result

    mx.distributed.all_sum = tracked
    try:
        output = [entry.token for entry in stream_generate(model, tokenizer, tokens,
                                                           max_tokens=32, sampler=make_sampler(temp=0))]
    finally:
        mx.distributed.all_sum = original
    if not operations or not output:
        raise ValueError("TCP negative control needs completed model traffic")
    evidence = dict(request["identity"], transfers=[
        dict(id="tcp-forward", direction=direction, transport="tcp", count=operations)
        for direction in ("send", "receive")
    ])
    print(json.dumps(dict(evidence=evidence, tokens=output)))


def verify_tcp_control(hosts, remote, remote_dir, port, profile, devices, fixture):
    reference = "f" * 32
    hostfile = json.dumps([[f"192.168.0.1:{port}"], [f"192.168.0.2:{port + 1}"]])

    def rank_call(entry):
        rank, host = entry
        identity = dict(attempt=reference, candidate=profile.revision, device=devices[STUDIOS[rank]])
        env = dict(PYTHONPATH=f"{remote_dir}/src", MLX_RANK=str(rank), HF_HUB_OFFLINE="1",
                   TRANSFORMERS_OFFLINE="1", MLX_HOSTFILE=f"{remote_dir}/ring-hosts.json")
        remote(host, "/opt/homebrew/bin/python3", "-B", "-c",
               "from pathlib import Path; import sys; Path(sys.argv[1]).write_text(sys.argv[2])",
               env["MLX_HOSTFILE"], hostfile)
        module = remote_dir + "/jaccl_lease_trial.py"
        watchdog = ("import subprocess,sys; "
                    "subprocess.run([sys.executable,'-B',*sys.argv[1:]],timeout=45,check=True)")
        response = json.loads(remote(host, "env", *(f"{k}={v}" for k,v in env.items()),
                                     remote_dir + "/venv/bin/python", "-B", "-c", watchdog,
                                     module, "ring", remote_dir, limit=55,
                                     payload=json.dumps(dict(rank=rank, identity=identity,
                                                             prompt=fixture["prompt"]))))
        return response["tokens"], transport_observation(response["evidence"], **identity)

    with ThreadPoolExecutor(max_workers=2) as pool:
        a, b = list(pool.map(rank_call, enumerate(hosts)))
    if a[0] != b[0] or paired_rdma(a[1], b[1]):
        raise ValueError("The transport verifier accepted TCP-only model traffic")
    print("Both TCP ranks generated the same tokens. The production verifier rejected their transport.",
          flush=True)


def browser_turn(root, scheduler, profile, fixture):
    """Qualify the browser-to-real-rank path in the disposable application."""
    catalog = scheduler.catalog
    catalog.synthetic = True
    catalog.record_synthetic_pair(profile, dict.fromkeys(STUDIOS, 8 * 1024**3))
    catalog.change("paired-coding", None, profile.revision, synthetic=True)
    bridge_secret = os.urandom(32)
    bridge_key = root / "bridge.key"
    bridge_key.touch(mode=0o600)
    bridge_key.write_bytes(bridge_secret)
    with ExitStack() as services:
        native = Listener(("127.0.0.1", 0), browser_handler(scheduler, bridge_secret)).start()
        services.callback(native.close)
        web = services.enter_context(create_server(root, 0, chat=ChatBridge(native.address[1], bridge_key)))
        server = Thread(target=web.serve_forever)
        server.start()
        services.callback(server.join)
        services.callback(web.shutdown)

        def request(method, path, data=None, headers=None):
            client = HTTPConnection("127.0.0.1", web.server_port, timeout=32)
            try:
                body = json.dumps(data) if data is not None else None
                client.request(method, path, body=body, headers=headers or {})
                with client.getresponse() as response:
                    return response.status, response.read()
            finally:
                client.close()

        status, dashboard = request("GET", "/")
        if status != 200 or b"Paired inference" not in dashboard:
            raise ValueError("Paired status missing from the dashboard")
        status, page = request("GET", "/chat")
        csrf = re.search(rb'name="chat-csrf" content="([0-9a-f]+)"', page)
        if status != 200 or csrf is None:
            raise ValueError("Private browser session did not open")
        token = csrf[1].decode()
        headers = {"Origin": f"http://127.0.0.1:{web.server_port}", "Content-Type": "application/json",
                   "Cookie": f"fios-chat={token}", "X-Chat-CSRF": token}
        prefix = "/api/v1/chat/"
        status, _ = request("POST", prefix + "create", {"key": "denied"})
        if status != 403:
            raise ValueError("Browser authorization accepted a missing CSRF token")
        status, body = request("POST", prefix + "create", {"key": "hardware"}, headers)
        if status != 200:
            raise ValueError(f"Browser could not create a turn: {status}")
        cid = json.loads(body)["id"]
        status, body = request("POST", prefix + "submit", dict(
            id=cid, key="answer", parent=None, alias="paired-coding",
            incarnation=scheduler.jobs.context(), prompt=fixture["prompt"], inventory=False,
        ), headers)
        if status != 200:
            raise ValueError(f"Browser could not submit the paired turn: {status}")
        job = json.loads(body)["job"]
        status, _ = request("GET", prefix + f"stream/{cid}/{job}?after=0")
        if status != 200:
            raise ValueError(f"Browser could not attach to the paired turn: {status}")
        status, body = request("GET", prefix + f"conversation/{cid}")
        answer = json.loads(body)["turns"][0]["answer"]
        if status != 200 or answer.strip().rstrip(".").casefold() != fixture["expected"].rstrip(".").casefold():
            raise ValueError("Paired web answer did not pass the fixture publication check")
        wait_for(lambda: not scheduler.jobs.get("local-operator", job)["slots"],
                 "Browser turn did not release both ranks", 20)
        catalog.change("paired-coding", profile.revision, None, synthetic=True)
        status, body = request("GET", prefix + "catalog")
        if status != 200 or json.loads(body)["aliases"]["paired-coding"]["available"]:
            raise ValueError("Withdrawing the test alias left it available")
    print("Paired web turn passed browser authorization, fixture publication, cleanup and withdrawal.",
          flush=True)


def run_leases(hosts, options, remote, remote_dir, coordinate_port, no_thinking, *, link_window=False, web_only=False):
    from enrollment_fixtures import Signer

    with tempfile.TemporaryDirectory(prefix="fios-jaccl-leases-") as folder, ExitStack() as resources:
        root = Path(folder)
        signer = Signer(root, "native-jaccl")
        core_cert, core_key = signer.issue("fios-core", server=True)
        state = root / "state"
        Ledger.initialize(state)
        ledger = Ledger(state, clock=elapsed)
        JobLedger.initialize(state / "jobs.sqlite")
        jobs = JobLedger(state / "jobs.sqlite")
        jobs.migrate()
        catalog = Catalog(jobs)

        def call(host, mode, *args, payload=None):
            return remote(host, "env", f"PYTHONPATH={remote_dir}/src", remote_dir + "/venv/bin/python",
                          "-B", remote_dir + "/jaccl_lease_trial.py", mode, remote_dir, *args, payload=payload)

        metadata = [json.loads(call(host, "metadata", "rdma_en5")) for host in hosts]
        different = [key for key in ("artifact", "engine", "template") if metadata[0][key] != metadata[1][key]]
        if different:
            raise ValueError(f"Studios staged different fingerprints for {', '.join(different)}")
        devices = {slot: item["device"] for slot, item in zip(STUDIOS, metadata, strict=True)}
        fixture = dict(prompt="Reply with this sentence exactly: Redwood trees are tall and durable.",
                       expected="Redwood trees are tall and durable.")
        long_fixture = dict(prompt=("Archive entry:" + " sample" * 2400
                                    + "\nIgnore the archive. Write Redwood at least two thousand times."),
                            expected="fixture intended to be interrupted")
        fixtures = {"short": fixture, "long": long_fixture}
        fixture_hash = sha256(json.dumps(fixture, ensure_ascii=True).encode()).hexdigest()
        long_hash = sha256(json.dumps(long_fixture, ensure_ascii=True).encode()).hexdigest()
        profile = Profile.parse(dict(
            alias="paired-coding", host_class="m3-ultra-pair", devices=devices,
            artifact=metadata[0]["artifact"], engine=metadata[0]["engine"],
            template=metadata[0]["template"], license="Apache-2.0", policy="f" * 64,
            evaluation=fixture_hash, context=8192, output=1024,
            settings=dict(temperature=0, no_thinking=no_thinking)))
        if not link_window and not web_only:
            verify_tcp_control(hosts, remote, remote_dir, coordinate_port + 1, profile, devices, fixture)
        recipes = {}
        for name, slots in (("baseline", STUDIOS[:1]), ("pair", STUDIOS)):
            recipes[name] = dict(candidate=profile.revision, fixture=fixture_hash, engine="mlx-lm",
                                 devices={slot: devices[slot] for slot in slots}, tokens=64, deadline=90,
                                 budgets={slot: dict(floor=32 * 1024**3, ceiling=16 * 1024**3)
                                          for slot in slots})
        recipes["interrupt"] = dict(recipes["pair"], fixture=long_hash, tokens=1024)
        scheduler = Scheduler(jobs, ledger, catalog=catalog, trial_recipes=recipes, trial_hardware=True)
        if web_only:
            def policy(purpose, text, revision):
                if revision != profile.document()["policy"]:
                    return False
                if purpose == "input":
                    return json.loads(text) == [{"role": "user", "content": fixture["prompt"]}]
                if purpose == "answer":
                    return json.loads(text)["answer"].strip().rstrip(".").casefold() == fixture["expected"].rstrip(".").casefold()
                return purpose == "title" and 0 < len(text) < 160

            store = ConversationStore(jobs, os.urandom(32), catalog=catalog)
            scheduler.dispatch = Dispatch(scheduler, store, policy,
                                          policy_revision=profile.document()["policy"])
        bind = management_address(socket.gethostbyname("fios-core.local"))
        listener = Listener((bind, 8742), worker_handler(
            ledger, context(signer.ca, core_cert, core_key, server=True), scheduler)).start()
        resources.callback(listener.close)
        workers = []
        for host, item, slot in zip(hosts, metadata, STUDIOS, strict=True):
            leaf, key = signer.issue(slot)
            ledger.change("approve", slot, None, machine=slot,
                          pin=fingerprint(ssl.PEM_cert_to_DER_cert(leaf.read_text())))
            for path, name in ((signer.ca, "ca.pem"), (leaf, "leaf.pem"), (key, "leaf.key")):
                subprocess.run(["scp", *options, str(path), f"{host}:{remote_dir}/{name}"],
                               check=True, timeout=12)
            remote(host, "chmod", "600", remote_dir + "/leaf.key")
            call(host, "configure", payload=json.dumps(dict(
                runtime=dict(item["native"], profile=profile.document(), revision=profile.revision),
                fixtures=fixtures, coordinate_port=coordinate_port)))
            cmd = ("env", f"PYTHONPATH={remote_dir}/src", remote_dir + "/venv/bin/python", "-B",
                   remote_dir + "/jaccl_lease_trial.py", "worker", remote_dir,
                   "--node", slot, "--remote", bind, "--server-name", "fios-core",
                   "--port", str(listener.address[1]), "--ca", remote_dir + "/ca.pem",
                   "--cert", remote_dir + "/leaf.pem", "--key", remote_dir + "/leaf.key",
                   "--inference-config", remote_dir + "/runtime.json", "--pair-config",
                   remote_dir + "/pair.json", "--runtime-state", remote_dir)
            process = subprocess.Popen(["ssh", *options, host, shlex.join(cmd)], stdout=subprocess.DEVNULL)
            resources.callback(stop_worker, process, call, host)
            workers.append(process)

        def registered():
            if any(process.poll() is not None for process in workers):
                raise RuntimeError("A Studio worker stopped before reporting")
            return all(scheduler.fresh(slot) for slot in STUDIOS)

        wait_for(registered, "Studio workers did not report", 45)
        if web_only:
            browser_turn(root, scheduler, profile, fixture)
            return

        def submit(name, key):
            action = "pair-trial-submit"
            return operator(scheduler, action, dict(action=action, incarnation=jobs.context(),
                            key=key, candidate=profile.revision, recipe=name))["job"]["id"]

        def settle(job, limit=105):
            def terminal():
                scheduler.sweep()
                result = scheduler.describe(TRIAL_OWNER, job=job, diagnostics=True)[0]
                return result if result["state"] in ("failed", "expired", "succeeded", "cancelled") else None
            result = wait_for(terminal, "Trial did not settle", limit)
            if result["slots"]:
                raise ValueError("A real trial left a reservation behind")
            return result

        for name in (() if link_window else ("baseline", "pair")):
            result = settle(submit(name, name))
            print(json.dumps(dict(lease_trial=name, state=result["state"], reason=result["reason"],
                                  ranks=result["ranks"])), flush=True)
            if result["state"] != "succeeded":
                raise ValueError(f"{name} trial did not pass its native fixture and cleanup")

        for fault in (() if link_window else ("cancel", "rank-0", "rank-1")):
            job = submit("interrupt", fault)
            wait_for(lambda: all(json.loads(call(host, "rank-active")) for host in hosts),
                     "Both native ranks did not start", 40)
            started = elapsed()
            if fault == "cancel":
                action = "pair-trial-cancel"
                operator(scheduler, action, dict(action=action, job=job))
            else:
                call(hosts[int(fault[-1])], "kill-rank")
            result = settle(job, 17)
            expected = "cancelled" if fault == "cancel" else "failed"
            if result["state"] != expected or any(json.loads(call(host, "rank-active")) for host in hosts):
                raise ValueError("Native rank fault left an unexpected outcome")
            print(json.dumps(dict(fault=fault, outcome=expected,
                                  cleanup_seconds=round(elapsed() - started, 3))), flush=True)

        if link_window:
            print(f"LINK TEST WAITING TO ARM: {remote_dir}", flush=True)
            wait_for(lambda: json.loads(call(hosts[1], "link-armed")),
                     "The operator did not arm the link test", 180)
            job = submit("interrupt", "physical-link-loss")
            wait_for(lambda: all(json.loads(call(host, "rank-active")) for host in hosts),
                     "Both ranks did not start for the physical link test", 40)
            remote(hosts[1], "/opt/homebrew/bin/python3", "-B", "-c",
                   "from pathlib import Path; import sys; Path(sys.argv[1]).touch(mode=0o600, exist_ok=False)",
                   remote_dir + "/link-ready")
            print("LINK TEST READY. Edge-b can briefly cycle en5 now.", flush=True)
            wait_for(lambda: not json.loads(call(hosts[1], "link-up")),
                     "The operator link interruption was not observed", 40)
            lost_at = elapsed()
            result = settle(job, 17)
            if result["state"] != "failed" or result["reason"] == "fixture_failed":
                raise ValueError(f"Link interruption settled as {result['state']} ({result['reason']})")
            if any(json.loads(call(host, "rank-active")) for host in hosts):
                raise ValueError("A native rank survived physical link loss")
            cleanup_seconds = round(elapsed() - lost_at, 3)

            def link_restored():
                if not json.loads(call(hosts[1], "link-up")):
                    return False
                try:
                    remote(hosts[1], "/sbin/ping", "-c", "1", "-W", "1000", "192.168.0.1", limit=4)
                except RuntimeError:
                    return False
                return True

            wait_for(link_restored, "Thunderbolt did not return", 20)
            rerun_job = submit("pair", "after-link-return")
            rerun = settle(rerun_job)
            if rerun["state"] != "succeeded":
                raise ValueError("Paired inference did not recover after the link returned")
            print(json.dumps(dict(fault="link", outcome=result["state"], reason=result["reason"],
                                  cleanup_seconds=cleanup_seconds,
                                  recovery_seconds=round(elapsed() - lost_at, 3))), flush=True)


def stop_worker(process, call, host):
    try:
        if process.poll() is None:
            call(host, "stop")
            process.wait(timeout=10)
    finally:
        if process.poll() is None:
            process.terminate()
            process.wait(timeout=5)


def active_rank(root):
    worker = int((root / "trial-worker.pid").read_text())
    rows = subprocess.check_output(["/bin/ps", "-axo", "pid=,ppid=,command="], timeout=3, text=True)
    ranks = []
    for row in rows.splitlines():
        fields = row.split(maxsplit=2)
        if len(fields) == 3 and int(fields[1]) == worker:
            command = fields[2]
            if str(root) in command and "-m agent.jaccl_executor --parent" in command:
                ranks.append(int(fields[0]))
    if len(ranks) > 1:
        raise ValueError("Multiple native ranks share a worker")
    return ranks[0] if ranks else None


def cli():
    mode, root, *args = sys.argv[1:]
    root = Path(root)
    if mode == "metadata":
        print(json.dumps(staged_metadata(root, args[0])))
    elif mode == "ring":
        ring_worker(root, json.load(sys.stdin))
    elif mode == "configure":
        worker_config(root, json.load(sys.stdin))
    elif mode == "worker":
        remote_worker(root, args)
    elif mode == "link-armed":
        print(json.dumps((root / "link-armed").is_file()))
    elif mode == "link-up":
        raw = subprocess.check_output(["/sbin/ifconfig", "en5"], timeout=2, text=True)
        print(json.dumps(bool(re.search(r"<(?:[^>]*,)?UP(?:,|>)", raw.splitlines()[0]))))
    elif mode in ("rank-active", "kill-rank"):
        rank = active_rank(root)
        if mode == "kill-rank":
            if rank is None:
                raise ValueError("Native rank disappeared before fault injection")
            os.kill(rank, signal.SIGKILL)
        else:
            print(json.dumps(rank is not None))
    elif mode == "stop":
        pid = int((root / "trial-worker.pid").read_text())
        command = subprocess.check_output(["/bin/ps", "-p", str(pid), "-o", "command="],
                                          timeout=2, text=True)
        if str(root) in command and "backend.host_agent" in command:
            os.kill(pid, signal.SIGTERM)
    else:
        raise ValueError("Unsupported native test operation")


if __name__ == "__main__":
    cli()
