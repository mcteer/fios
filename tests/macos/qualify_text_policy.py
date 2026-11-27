"""Evaluate a local candidate on fixed decisions without serving user content."""

import argparse
import json
from pathlib import Path
import time

from agent.publication_prompt import messages_for, prompt_digest

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", type=Path, required=True)
    parser.add_argument("--split", choices=("development", "holdout", "final", "wire", "release"), required=True)
    parser.add_argument("--variant", choices=("baseline", "examples", "framed"), default="baseline")
    parser.add_argument("--max-new-tokens", type=int, choices=(8, 256, 768), default=8)
    args = parser.parse_args()

    from mlx_lm import load, generate
    from mlx_lm.sample_utils import make_sampler

    cases_path = Path(__file__).parents[1] / "fixtures" / "chat" / "policy_eval.json"
    cases = json.loads(cases_path.read_text())[args.split]
    model, tokenizer = load(str(args.model))
    sampler = make_sampler(temp=0)
    report = []
    for case in cases:
        messages = messages_for(case, args.variant)
        prompt = tokenizer.apply_chat_template(messages, tokenize=False, add_generation_prompt=True)
        start = time.monotonic()
        response = generate(model, tokenizer, prompt=prompt, max_tokens=args.max_new_tokens,
                            sampler=sampler, verbose=False).strip()
        if response.startswith("<think>") and "</think>" in response:
            response = response.split("</think>", 1)[1].strip()
        decision = "allow" if response == "ALLOW" else "withhold"
        report.append(dict(id=case["id"], decision=decision,
                           well_formed=response in {"ALLOW", "WITHHOLD"},
                           passed=(decision == "allow") == case["allow"],
                           seconds=round(time.monotonic() - start, 3)))
    print(json.dumps({"split": args.split, "variant": args.variant,
                      "policy_prompt_sha256": prompt_digest(args.variant),
                      "all_passed": all(item["passed"] and item["well_formed"] for item in report),
                      "results": report}, indent=2))


if __name__ == "__main__":
    main()
