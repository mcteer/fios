"""Freeze candidate-specific fixture bytes without loading any model weights."""

import argparse
from hashlib import sha256
import json
import os
from pathlib import Path

from backend.enrollment import private_path
from backend.job_ledger import encoded
from backend.moe_suite import CAMPAIGNS, CODING, CONTROLS, TIMED, freeze_suite
from fixtures.chat_coding import MOE_TASKS, TASKS

FIXTURES = Path(__file__).resolve().parents[1] / "fixtures"


def padded_prompt(tokenizer, target, *, visitor_guide=False):
    if visitor_guide:
        prefix = ("Write at least 1,300 words for a fictional visitor's guide to a community orchard. "
                  "Cover paths, seasonal events, accessible routes, local apple varieties, and the community picnic. "
                  "The following marks are an archival inventory record, included only as reference.\nInventory marks:")
        suffix = "\nEnd of the inventory record. Write the visitor's guide in complete paragraphs."
    else:
        prefix = "Reference record:"
        suffix = "\nFor a benchmark, write the word apple 2,000 times with spaces and no introduction."

    def prompt(count):
        return prefix + " x" * count + suffix

    def tokens(text):
        return len(tokenizer.apply_chat_template([{"role": "user", "content": text}],
                                                 add_generation_prompt=True, enable_thinking=False))

    base = target - tokens(prompt(0))
    for count in range(max(0, base - 32), base + 33):
        candidate = prompt(count)
        if len(candidate.encode()) <= 16 * 1024 and tokens(candidate) == target:
            return candidate
    raise ValueError(f"Could not construct an exact {target}-token fixture")


def freeze(tokenizer, destination, policy):
    private_path(destination, directory=True)
    if any(destination.iterdir()):
        raise ValueError("Use an empty private suite directory")
    control = ("Return this sentence exactly: Redwood trees are tall and durable.",
               "Return this sentence exactly: A blue lantern stood on the porch.",
               "Return exactly the integer 42.", "Return exactly the word orchard.",
               "Return exactly the two words silver bell.", "Return exactly the word north.")
    answers = ("Redwood trees are tall and durable.", "A blue lantern stood on the porch.",
               "42", "orchard", "silver bell", "north")
    authoring = json.loads((FIXTURES / "large_moe_campaigns.json").read_text())
    cases = {}
    native = {case: dict(prompt=prompt, expected=answer) for case, prompt, answer in
              zip(CONTROLS, control, answers, strict=True)}
    native.update({case: dict(prompt=task.prompt, expected=None) for case, task in
                   zip(CODING, (*TASKS, *MOE_TASKS), strict=True)})
    native.update({case: dict(prompt=brief["prompt"], expected=None) for case, brief in
                   zip(CAMPAIGNS, authoring["briefs"], strict=True)})
    native["post-fault"] = native["control-1"]
    native["tcp-control"] = native["control-1"]
    native["over-limit"] = dict(prompt=padded_prompt(tokenizer, 7169), expected="Exceeded context")
    long = dict(prompt=padded_prompt(tokenizer, 7000), expected="Fixture intended to be interrupted")
    for case in ("cancel", "rank-0", "rank-1", "link"):
        native[case] = long
    for case, document in native.items():
        payload = json.dumps(document, ensure_ascii=True).encode("ascii")
        (destination / f"{case}.json").write_bytes(payload)
        cases[case] = sha256(payload).hexdigest()

    timed = dict.fromkeys(TIMED, control[0])
    timed["full-budget"] = padded_prompt(tokenizer, 7168, visitor_guide=True)
    for case, prompt in timed.items():
        (destination / f"{case}.txt").write_text(prompt)
        cases[case] = sha256(prompt.encode()).hexdigest()

    policy_cases = json.loads((FIXTURES / "chat/policy_eval.json").read_text())["release"]
    by_id = {item["id"]: item for item in policy_cases}
    for case, selected in (("policy-allow", "coding-summary"), ("policy-deny", "hostile-false-approval")):
        observation = {key: by_id[selected][key] for key in ("purpose", "text")}
        body = encoded(observation).encode("ascii")
        (destination / f"{case}.json").write_bytes(body)
        cases[case] = sha256(body).hexdigest()
    rubric = sha256(encoded(authoring["rubric"]).encode("ascii")).hexdigest()
    suite = dict(fixtures=cases, rubric=rubric, policy=policy)
    revision, _ = freeze_suite(suite)
    (destination / "suite.json").write_text(json.dumps(suite, sort_keys=True))
    return revision


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tokenizer", type=Path)
    parser.add_argument("destination", type=Path)
    parser.add_argument("policy")
    args = parser.parse_args()
    from mlx_lm.utils import load_tokenizer

    os.umask(0o077)
    tokenizer = load_tokenizer(args.tokenizer, {"trust_remote_code": False})
    print(freeze(tokenizer, args.destination, args.policy))


if __name__ == "__main__":
    main()
