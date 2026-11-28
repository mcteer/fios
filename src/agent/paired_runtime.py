"""Launch one pinned native rank under the standard exclusive executor lock."""

from hashlib import sha256
from ipaddress import IPv4Address
import json
import os
from pathlib import Path
import re
import subprocess

from backend.enrollment import Rejected, STUDIOS, private_path
from backend.job_ledger import integer
from backend.pair_trial import GIB, LARGE_FLOOR, PAIR_ONLY, digest
from .macos_memory import footprint, headroom
from .native_runtime import NativeRuntime


class PairedRuntime(NativeRuntime):
    def __init__(self, path, state, node):
        private_path(path)
        with path.open("rb") as stream:
            raw = stream.read(64 * 1024 + 1)
        if len(raw) > 64 * 1024:
            raise ValueError("Paired runtime configuration exceeds its limit")
        config = json.loads(raw)
        fields = {"runtime", "devices", "coordinator", "port", "fixtures"}
        if not isinstance(config, dict) or config.keys() not in (fields, fields | {"large_stage"}):
            raise ValueError("Invalid paired runtime configuration")
        self.large_stage = config.get("large_stage")
        probe = None
        if "large_stage" in config:
            if (not isinstance(self.large_stage, dict) or self.large_stage.keys() != {"stage", "artifact"}
                    or self.large_stage["stage"] not in ("probe", "full")):
                raise ValueError("Invalid large-model stage")
            if self.large_stage["stage"] == "probe":
                probe = digest(self.large_stage["artifact"])
        super().__init__(Path(config["runtime"]), state, purpose="inference", probe_artifact=probe,
                         pair_only=self.large_stage is not None)
        if self.large_stage and self.large_stage["artifact"] != self.staged_artifact:
            raise ValueError("Pinned large-model stage does not match staged files")
        if self.entry != "mlx_lm.server" or node not in STUDIOS:
            raise ValueError("Paired runtime requires a Studio and a verified MLX-LM environment")
        self.rank = STUDIOS.index(node)
        self.devices = config["devices"]
        if (not isinstance(self.devices, list) or len(self.devices) != 2
                or any(not isinstance(name, str) or not re.fullmatch(r"rdma_en[0-9]{1,3}", name)
                       for name in self.devices)):
            raise ValueError("Paired runtime requires two approved Thunderbolt device names")
        self.coordinator = IPv4Address(config["coordinator"])
        if not self.coordinator.is_private or self.coordinator.is_loopback:
            raise ValueError("Paired runtime requires a private Thunderbolt coordinator")
        self.port = integer(config["port"], 1024, 65535)
        if "devices" not in self.profile_document or not isinstance(config["fixtures"], dict):
            raise ValueError("Expected a paired profile and reviewed fixtures")
        self.device_fingerprint = self.profile_document["devices"][node]
        self.host_build = subprocess.check_output(["/usr/bin/sw_vers", "-buildVersion"],
                                                 timeout=2, text=True).strip()
        self.no_thinking = self.profile_document["settings"].get("no_thinking", False)
        self.fixtures = {}
        for checksum, path in config["fixtures"].items():
            with Path(path).open("rb") as stream:
                fixture = stream.read(20 * 1024 + 1)
            if len(fixture) > 20 * 1024 or sha256(fixture).hexdigest() != digest(checksum):
                raise ValueError("Unexpected reviewed fixture digest")
            data = json.loads(fixture)
            if (not isinstance(data, dict) or set(data) != {"prompt", "expected"}
                    or not isinstance(data["prompt"], str) or not data["prompt"]
                    or (data["expected"] is not None
                        and (not isinstance(data["expected"], str) or not data["expected"]))):
                raise ValueError("Invalid reviewed fixture")
            self.fixtures[checksum] = data
        self.prepared = None
        self.trial_ceiling = None
        self.resource_budget = None
        self.link_required = False

    def prepare(self, offer):
        if offer["profile"] != self.revision:
            raise Rejected("profile_changed", 409)
        trial = offer.get("trial")
        if trial and (trial["engine"] != "mlx-lm" or trial["fixture"] not in self.fixtures):
            raise Rejected("invalid_recipe", 409)
        if self.large_stage:
            self.check_large_offer(trial or offer.get("pair"))
        elif trial and "placement" in trial:
            raise Rejected("invalid_recipe", 409)
        assignment = trial or offer["pair"]
        if assignment["device"] != self.device_fingerprint:
            raise Rejected("profile_changed", 409)
        self.link_required = not trial or trial["world_size"] == 2
        self.check_link()
        self.trial_ceiling = (trial or assignment)["budget"]["ceiling"] if trial or self.large_stage else None
        self.resource_budget = None
        rank = assignment["rank"]
        if rank != self.rank and not (trial and trial["world_size"] == 1 and rank == 0):
            raise Rejected("fenced", 409)
        self.prepared = (offer["job"], offer["generation"], offer["grant"], trial, offer.get("pair"))

    def check_large_offer(self, trial):
        if (not trial or trial.get("placement") != PAIR_ONLY or trial.get("world_size") != 2
                or trial.get("rank") != self.rank
                or trial.get("stage") != self.large_stage["stage"]
                or trial.get("artifact") != self.profile_document["artifact"]
                or trial.get("staged_artifact") != self.staged_artifact):
            raise Rejected("large_trial_placement", 409)
        floor = integer(trial["budget"]["floor"], LARGE_FLOOR, 256 * GIB)
        integer(trial["budget"]["ceiling"], 1, 256 * GIB - floor)

    def check_link(self):
        if not self.link_required:
            return
        device = self.devices[self.rank]
        try:
            interface = subprocess.check_output(["/sbin/ifconfig", device.removeprefix("rdma_")],
                                                timeout=1, text=True)
            flags = re.search(r"<([^>]+)>", interface)
            if flags is None or "UP" not in flags[1].split(","):
                raise Rejected("transport_unavailable", 409)
            details = subprocess.check_output(["/usr/bin/ibv_devinfo", "-d", device],
                                              timeout=1, text=True)
        except (OSError, subprocess.SubprocessError) as error:
            raise Rejected("transport_unavailable", 409) from error
        guid = re.search(r"^\s*node_guid:\s*([0-9a-fA-F:]+)\s*$", details, re.MULTILINE)
        if "PORT_ACTIVE" not in details or "Thunderbolt" not in details or not guid:
            raise Rejected("transport_unavailable", 409)
        active = f"{device}:{guid[1].replace(':', '').lower()}:{self.host_build}"
        if sha256(active.encode("ascii")).hexdigest() != self.device_fingerprint:
            raise Rejected("profile_changed", 409)

    def launch_rank(self, offer, payload, deadline):
        trial, pair = offer.get("trial"), offer.get("pair")
        key = (offer["job"], offer["generation"], offer["grant"], trial, pair)
        if key != self.prepared:
            raise Rejected("fenced", 409)
        self.prepared = None
        rank = (trial or pair)["rank"]
        world = trial["world_size"] if trial else 2
        expected = None
        input_limit, output_limit = self.limits
        if trial:
            fixture = self.fixtures[trial["fixture"]]
            messages = [{"role": "user", "content": fixture["prompt"]}] if rank == 0 else None
            expected = fixture["expected"]
            if (expected is None) != ("review" in trial):
                raise Rejected("invalid_recipe", 409)
            output_limit = min(output_limit, trial["tokens"])
        elif payload is None:
            messages = None
        else:
            messages, limits = payload
            if self.limits != tuple(limits):
                raise Rejected("profile_changed", 409)
        remaining = deadline - self.clock()
        if remaining <= 0:
            raise Rejected("runtime_deadline", 504)
        env = self.environment()
        env["PYTHONPATH"] = str(Path(__file__).resolve().parents[1])
        if world == 2:
            device_file = self.state / "pair-devices.json"
            payload_map = json.dumps([[None, [self.devices[0]]], [[self.devices[1]], None]])
            try:
                fd = os.open(device_file, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
            except FileExistsError:
                pass
            else:
                with os.fdopen(fd, "w") as stream:
                    stream.write(payload_map)
            private_path(device_file)
            if device_file.read_text() != payload_map:
                raise Rejected("profile_changed", 409)
            env.update(MLX_RANK=str(rank), MLX_IBV_DEVICES=str(device_file),
                       MLX_JACCL_COORDINATOR=f"{self.coordinator}:{self.port}")
        identity = dict(attempt=offer["job"], candidate=self.revision, device=(trial or pair)["device"])
        work = dict(rank=rank, world_size=world, messages=messages, expected=expected,
                    input_limit=input_limit, output_limit=output_limit, identity=identity,
                    no_thinking=self.no_thinking, temperature=self.temperature)
        if self.large_stage:
            budget = (trial or pair)["budget"]
            from .moe_watchdog import swap_used

            self.resource_budget = dict(
                memory=int(subprocess.check_output(["/usr/sbin/sysctl", "-n", "hw.memsize"],
                                                   timeout=1)), baseline=swap_used(),
                floor=budget["floor"], ceiling=budget["ceiling"])
            available, pressure = headroom(self.resource_budget["memory"])
            if pressure != "normal" or available < sum(budget.values()):
                raise Rejected("unsafe_rank_resources", 409)
            work["watchdog"] = self.resource_budget
            work["staged_artifact"] = self.staged_artifact
            if trial and "review" in trial:
                work["review"] = True
        if self.large_stage:
            from .rank_monitor import supervised_rank

            def start(observer):
                return self.spawn("agent.jaccl_executor", (str(self.model),), env, capture=True,
                                  observers=(observer,))

            child, stdout, observation = supervised_rank(start, work, remaining)
        else:
            child = self.spawn("agent.jaccl_executor", (str(self.model),), env, capture=True)
            stdout, _ = child.communicate(json.dumps(work).encode("utf-8"), timeout=remaining)
        if child.returncode == 65 and self.large_stage:
            raise Rejected("context_limit", 413)
        if child.returncode == 78 and self.large_stage:
            raise Rejected("unsafe_rank_resources", 409)
        if child.returncode or len(stdout) > 96 * 1024:
            raise Rejected("runtime_failure", 503)
        result = json.loads(stdout)
        if self.large_stage:
            result["diagnostics"]["phase_observation"] = observation
        return result

    def check_budget(self):
        with self.lock:
            child = self.process
            if self.trial_ceiling is None or child is None or child.poll() is not None:
                return
            try:
                _, peak = footprint(child.pid)
            except OSError:
                if child.poll() is None:
                    raise
                return
            if peak >= self.trial_ceiling:
                raise Rejected("trial_budget", 409)
            if self.resource_budget:
                from .moe_watchdog import swap_used

                available, pressure = headroom(self.resource_budget["memory"])
                if (pressure != "normal" or available < self.resource_budget["floor"]
                        or swap_used() > self.resource_budget["baseline"]):
                    raise Rejected("unsafe_rank_resources", 409)

    def run_trial(self, offer, deadline):
        result = self.launch_rank(offer, None, deadline)
        return (result["answer"], result["diagnostics"]) if "review" in offer["trial"] else result["diagnostics"]

    def run_chat(self, offer, payload, deadline):
        result = self.launch_rank(offer, payload, deadline)
        return result["answer"], result["usage"], result["diagnostics"]
