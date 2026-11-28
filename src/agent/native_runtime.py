"""A host-local native inference runner with fail-closed process ownership."""

import fcntl
from hashlib import file_digest, sha256
from http.client import HTTPConnection, HTTPException
import json
import os
import platform
from pathlib import Path
import signal
import subprocess
import threading
import time

from backend.enrollment import Rejected, private_path
from backend.job_ledger import encoded
from backend.model_catalog import Profile
from .publication_prompt import prompt_digest
from .inference import generate_text


def verify_model_manifest(model, files):
    """Verify the complete local set before a native serving process can load it."""
    recognized = {".json", ".jinja", ".model", ".safetensors", ".txt"}
    if not isinstance(files, dict) or not files or len(files) > 256:
        raise ValueError("Expected a pinned local model file manifest")
    staged = {path.name for path in model.iterdir() if path.suffix in recognized}
    if (set(files) != staged or "config.json" not in staged
            or not any(name.endswith(".safetensors") for name in staged)):
        raise ValueError("Model file manifest does not match the staged model")
    for name, expected in sorted(files.items()):
        path = model / name
        if (not isinstance(expected, str) or len(expected) != 64
                or path.is_symlink() or not path.is_file()):
            raise ValueError("Invalid staged model file")
        with path.open("rb") as stream:
            if file_digest(stream, "sha256").hexdigest() != expected:
                raise ValueError("Staged model file digest changed")


def digest_file(path):
    with path.open("rb") as stream:
        return file_digest(stream, "sha256").hexdigest()


def manifest_digest(document):
    return sha256(encoded(document).encode("ascii")).hexdigest()


def environment_root(engine):
    roots = list(engine.parent.parent.glob("lib/python*/site-packages"))
    if len(roots) != 1 or roots[0].is_symlink() or not roots[0].is_dir():
        raise ValueError("Expected one private virtual environment")
    return roots[0]


def deployment_stamp(engine, model):
    """Detect deployment changes after the startup digest verification."""
    root = environment_root(engine)
    paths = [engine, *model.iterdir(), *root.rglob("*")]
    signature = []
    for path in sorted(paths):
        raw = path.stat() if path == engine else path.lstat()
        signature.append((str(path), raw.st_ino, raw.st_size, raw.st_mtime_ns, raw.st_ctime_ns))
    return signature


def verify_environment(engine, manifest, entry, executable_digest, *, paired=False):
    """Pin installed package contents and launcher alongside the interpreter."""
    file = Path(manifest)
    private_path(file)
    with file.open("rb") as stream:
        raw = stream.read(16 * 1024 * 1024 + 1)
    if len(raw) > 16 * 1024 * 1024:
        raise ValueError("Runtime environment manifest is too large")
    expected = json.loads(raw)
    if not isinstance(expected, dict) or not expected:
        raise ValueError("Expected a pinned runtime environment")
    root = environment_root(engine)
    observed = {}
    for path in root.rglob("*"):
        if path.is_symlink():
            raise ValueError("Runtime environment contains a symbolic link")
        if path.is_file():
            name = path.relative_to(root).as_posix()
            if name not in expected:
                raise ValueError("Unlisted runtime environment file")
            observed[name] = digest_file(path)
    if observed != expected:
        raise ValueError("Runtime environment digest changed")
    launcher = digest_file(Path(__file__).with_name("native_executor.py"))
    adapter = digest_file(Path(__file__).with_name("inference.py"))
    identity = {"executable": executable_digest, "packages": expected,
                "entry": entry, "launcher": launcher, "adapter": adapter}
    if paired:
        identity["paired"] = {name: digest_file(Path(__file__).with_name(name)) for name in
                              ("paired_runtime.py", "jaccl_executor.py", "jaccl_transport.py",
                               "inference_worker.py")}
    return manifest_digest(identity)


class NativeRuntime:
    def __init__(self, path, state, *, clock=time.monotonic, require_manifest=False, purpose=None):
        private_path(Path(path))
        private_path(Path(state), directory=True)
        self.state = Path(state)
        with Path(path).open("rb") as stream:
            raw = stream.read(64 * 1024 + 1)
        if len(raw) > 64 * 1024:
            raise ValueError("Runtime configuration is too large")
        config = json.loads(raw)
        fields = {"revision", "model", "engine", "executable_sha256", "entry", "port"}
        hashed = fields | {"model_files"}
        if purpose == "inference":
            supported = (hashed | {"environment_manifest", "profile"},)
        elif purpose == "policy":
            supported = (hashed | {"environment_manifest"},)
        else:
            supported = (hashed,) if require_manifest else (fields, hashed)
        if not isinstance(config, dict) or config.keys() not in supported:
            raise ValueError("Invalid runtime configuration")
        for field in ("revision", "executable_sha256"):
            value = config[field]
            if not isinstance(value, str) or len(value) != 64 or any(c not in "0123456789abcdef" for c in value):
                raise ValueError("Invalid runtime digest")
        entry = config["entry"]
        if entry not in ("mlx_lm.server", "mlx_vlm.server"):
            raise ValueError("Unsupported native runtime entry")
        self.model = Path(config["model"])
        self.engine = Path(config["engine"])
        if (not self.model.is_absolute() or not self.model.is_dir()
                or not self.engine.is_absolute() or not self.engine.is_file()):
            raise ValueError("Use absolute verified runtime and model paths")
        with self.engine.open("rb") as stream:
            if file_digest(stream, "sha256").hexdigest() != config["executable_sha256"]:
                raise ValueError("Runtime executable digest changed")
        if "model_files" in config:
            verify_model_manifest(self.model, config["model_files"])
        if type(config["port"]) is not int or not 1 <= config["port"] <= 65535:
            raise ValueError("Invalid runtime port")
        self.revision, self.entry, self.port = config["revision"], entry, config["port"]
        self.profile_document = None
        self.temperature = 0
        self.limits = None
        self.verified_deployment = None
        if purpose:
            profile = Profile.parse(config["profile"]) if purpose == "inference" else None
            document = self.profile_document = profile.document() if profile else None
            paired = document is not None and "devices" in document
            artifact = manifest_digest(config["model_files"])
            environment = verify_environment(self.engine, config["environment_manifest"], entry,
                                             config["executable_sha256"], paired=paired)
            if purpose == "policy":
                identity = {"artifact": artifact, "engine": environment, "prompt": prompt_digest("framed"),
                            "worker": digest_file(Path(__file__).with_name("policy_worker.py"))}
                if manifest_digest(identity) != self.revision:
                    raise ValueError("Policy revision does not match the staged runtime and prompt")
            else:
                template = config["model_files"].get("chat_template.jinja",
                                                     config["model_files"].get("tokenizer_config.json"))
                if (profile.revision != self.revision or document["artifact"] != artifact
                        or document["engine"] != environment or document["template"] != template):
                    raise ValueError("Serving profile does not match the staged runtime")
                self.temperature = document["settings"]["temperature"]
                self.limits = document["context"] - document["output"], document["output"]
            self.verified_deployment = deployment_stamp(self.engine, self.model)
        self.clock = clock
        self.lock = threading.RLock()
        self.process = None
        self.descriptor = None
        self.interrupted = threading.Event()

    def acquire_executor(self):
        path = self.state / "runtime.lock"
        fd = os.open(path, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW | os.O_NONBLOCK, 0o600)
        try:
            private_path(path)
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            return fd
        except BaseException:
            os.close(fd)
            raise

    def environment(self):
        return {"PATH": "/usr/bin:/bin", "HF_HUB_OFFLINE": "1", "TRANSFORMERS_OFFLINE": "1",
                "HF_HOME": str(self.state / "hf"), "PYTHONNOUSERSITE": "1",
                "PYTHONDONTWRITEBYTECODE": "1"}

    def check_prompt(self, messages, limit, deadline):
        code = (
            "from transformers import AutoTokenizer\n"
            "import json,sys\n"
            "tokenizer=AutoTokenizer.from_pretrained(sys.argv[1],local_files_only=True,"
            "trust_remote_code=False)\n"
            "messages=json.load(sys.stdin)\n"
            "while True:\n"
            "    tokens=tokenizer.apply_chat_template(messages,tokenize=True,return_dict=False,"
            "add_generation_prompt=True)\n"
            "    if not tokens: raise SystemExit(1)\n"
            "    if len(tokens)<=int(sys.argv[2]): break\n"
            "    start=int(messages[0]['role']=='system')\n"
            "    if len(messages)<=start+1: raise SystemExit(1)\n"
            "    del messages[start:start+2]\n"
            "json.dump(messages,sys.stdout,ensure_ascii=True)\n"
        )
        remaining = deadline - self.clock()
        if remaining <= 0:
            raise Rejected("runtime_deadline", 504)
        helper = subprocess.run([str(self.engine), "-B", "-c", code, str(self.model), str(limit)],
                                input=json.dumps(messages).encode("ascii"), stdout=subprocess.PIPE,
                                stderr=subprocess.DEVNULL, env=self.environment(), timeout=min(5, remaining))
        if helper.returncode or len(helper.stdout) > 80 * 1024:
            raise Rejected("context_limit", 413)
        return json.loads(helper.stdout)

    def launch(self):
        self.spawn()

    def spawn(self, entry=None, arguments=(), environment=None, *, capture=False):
        if (self.verified_deployment is not None
                and self.verified_deployment != deployment_stamp(self.engine, self.model)):
            raise Rejected("profile_changed", 409)
        if platform.system() != "Darwin" or platform.machine() != "arm64":
            raise Rejected("native_macos_required", 409)
        if entry is None:
            entry = self.entry
            arguments = ("--model", str(self.model), "--host", "127.0.0.1", "--port", str(self.port))
            environment = self.environment()
        with self.lock:
            if self.interrupted.is_set():
                raise Rejected("fenced", 409)
            if self.process is not None:
                raise Rejected("runtime_busy", 409)
            self.descriptor = self.acquire_executor()
            if entry == "agent.jaccl_executor":
                launcher = ["-m", entry, "--parent", str(os.getpid())]
            else:
                path = Path(__file__).with_name("native_executor.py").resolve()
                launcher = [str(path), str(os.getpid()), entry]
            try:
                self.process = subprocess.Popen(
                    [str(self.engine), "-B", *launcher, *arguments],
                    env=environment, cwd=self.state, stdin=subprocess.PIPE if capture else subprocess.DEVNULL,
                    stdout=subprocess.PIPE if capture else subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                    start_new_session=True, pass_fds=(self.descriptor,))
                return self.process
            except BaseException:
                os.close(self.descriptor)
                self.descriptor = None
                raise

    def wait_ready(self, deadline):
        while self.clock() < deadline and not self.interrupted.is_set():
            with self.lock:
                if self.process is None or self.process.poll() is not None:
                    break
                pid = self.process.pid
            try:
                sockets = subprocess.run(
                    ["/usr/sbin/lsof", "-nP", "-a", "-p", str(pid), f"-iTCP:{self.port}",
                     "-sTCP:LISTEN", "-Fn"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                    text=True, timeout=min(2, max(0.05, deadline - self.clock())))
            except subprocess.TimeoutExpired:
                continue
            if f"n127.0.0.1:{self.port}" not in sockets.stdout.splitlines():
                self.interrupted.wait(0.1)
                continue
            client = HTTPConnection("127.0.0.1", self.port, timeout=0.25)
            try:
                # MLX-VLM opens its socket before background model loading ends.
                client.request("GET", "/health" if self.entry == "mlx_vlm.server" else "/v1/models")
                with client.getresponse() as result:
                    if result.status == 200:
                        if self.entry != "mlx_vlm.server":
                            return
                        body = result.read(16385)
                        if len(body) > 16384:
                            raise Rejected("runtime_unavailable", 503)
                        status = json.loads(body)
                        if not isinstance(status, dict):
                            raise Rejected("runtime_unavailable", 503)
                        if status.get("preload_failures"):
                            raise Rejected("runtime_model_load", 503)
                        model = status.get("loaded_model")
                        if (status.get("model_ready") is True and isinstance(model, str)
                                and Path(model).resolve() == self.model.resolve()):
                            return
            except (OSError, HTTPException):
                pass
            finally:
                client.close()
            self.interrupted.wait(0.1)
        raise Rejected("runtime_unavailable", 503)

    def arm(self):
        """Called by the owner before scheduling a new assignment."""
        with self.lock:
            if self.process is not None:
                raise Rejected("runtime_busy", 409)
            self.interrupted.clear()

    def generate(self, revision, messages, input_limit, output_limit, deadline, *,
                 preserve_context=False, on_first_generated=None, on_first_text=None):
        if revision != self.revision or (self.limits is not None and self.limits != (input_limit, output_limit)):
            raise Rejected("profile_changed", 409)
        if self.interrupted.is_set():
            raise Rejected("fenced", 409)
        checked = self.check_prompt(messages, input_limit, deadline)
        if preserve_context and checked != messages:
            raise Rejected("context_limit", 413)
        self.launch()
        self.wait_ready(deadline)
        duration = deadline - self.clock()
        if duration <= 0:
            raise Rejected("runtime_deadline", 504)
        return generate_text(self.port, checked, input_limit=input_limit, output_limit=output_limit,
                             timeout=duration, temperature=self.temperature,
                             on_first_generated=on_first_generated, on_first_text=on_first_text,
                             local_model=str(self.model) if self.entry == "mlx_vlm.server" else None)

    def stop(self):
        self.interrupted.set()
        with self.lock:
            if self.process is None:
                return
            process = self.process
            for signum, grace in ((signal.SIGTERM, 1), (signal.SIGKILL, 1)):
                try:
                    os.killpg(process.pid, signum)
                except ProcessLookupError:
                    pass
                try:
                    process.wait(timeout=grace)
                except subprocess.TimeoutExpired:
                    continue
                try:
                    os.killpg(process.pid, 0)
                except ProcessLookupError:
                    self.process = None
                    os.close(self.descriptor)
                    self.descriptor = None
                    return
            raise Rejected("cleanup_required", 409)

    def quiescent(self):
        with self.lock:
            if self.process is not None:
                return False
            try:
                fd = self.acquire_executor()
            except BlockingIOError:
                return False
            os.close(fd)
            return True
