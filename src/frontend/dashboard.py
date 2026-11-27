"""Server-rendered cluster overview and its stylesheet."""

from datetime import datetime, timezone
from html import escape
from pathlib import Path
from string import Template

STATIC = Path(__file__).parent
PAGE = Template((STATIC / "overview.html").read_text(encoding="utf-8"))
STYLE = (STATIC / "style.css").read_bytes()
STATES = {"awaiting": "Awaiting sample", "reporting": "Reporting",
          "stale": "Stale sample", "invalid": "Invalid sample"}


def timestamp(seconds):
    return datetime.fromtimestamp(seconds, tz=timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")


def state_label(host):
    return {"not_enrolled": "Not enrolled", "revoked": "Revoked",
            "unknown": "Telemetry unavailable"}.get(host.get("enrollment"), STATES[host["state"]])


def render(nodes, now, *, chat=False):
    cards = []
    for host in nodes:
        sample = host["observation"]
        measurements = "<p class='empty'>No usable host observation.</p>"
        if sample:
            values = [
                ("Physical memory", f"{sample['memory_bytes'] / 1024**3:.1f} GiB"),
                ("Logical CPUs", str(sample["logical_cpus"])),
                ("Load average (1 min)", f"{sample['load_1m']:.2f}"),
                ("Observed", timestamp(sample["sampled_at"])),
            ]
            measurements = "<dl>" + "".join(
                f"<div><dt>{escape(k)}</dt><dd>{escape(v)}</dd></div>" for k, v in values
            ) + "</dl>"
        cards.append(
            f"<article><header><div><p class='role'>{escape(host['role'])}</p>"
            f"<h2>{escape(host['id'])}</h2></div>"
            f"<span class='state {host['state']}'>{state_label(host)}</span></header>"
            f"<p class='config'>{escape(host['hardware'])} · {escape(host['chip'])} · "
            f"{host['configured_gb']} GB configured</p>{measurements}</article>"
        )
    count = sum(host["state"] == "reporting" for host in nodes)
    return PAGE.substitute(cards="".join(cards), reporting=count, total=len(nodes),
                           checked=timestamp(now),
                           chat='<a href="/chat">Private chat</a>' if chat else "").encode()
