"""Present model-blind campaign samples to an authorized local reviewer."""

import argparse
import json
from pathlib import Path
import random
import sys

from backend.enroll import command
from backend.moe_suite import CAMPAIGNS
from grade_moe_sql import review_sample


DIMENSIONS = ("canon_fidelity", "narrative_clarity", "session_usability")
BRIEFS = Path(__file__).resolve().parents[1] / "fixtures" / "large_moe_campaigns.json"


def review(path, selections):
    authoring = json.loads(BRIEFS.read_text())
    briefs = dict(zip(CAMPAIGNS, authoring["briefs"], strict=True))
    cases = [(case, blind, briefs[case]) for case, blind in selections.items()]
    random.SystemRandom().shuffle(cases)
    print(json.dumps(authoring["rubric"], indent=2))
    for position, (case, blind, brief) in enumerate(cases, 1):
        answer, checksum = review_sample(path, blind, case, "campaign")
        displayed = "".join(character if character.isprintable() or character in "\n\t"
                            else ascii(character)[1:-1] for character in answer)
        scene = brief["prompt"].split(" Canon:", 1)[0]
        print(f"Sample {position} of {len(cases)} · {scene}\n\nBrief\n{brief['prompt']}\n\nAnswer\n{displayed}\n")
        while True:
            reply = input("Canon fidelity, narrative clarity, session usability (for example, 4 5 4) > ")
            scores = reply.replace(",", " ").split()
            if len(scores) == len(DIMENSIONS) and all(score in ("1", "2", "3", "4", "5") for score in scores):
                break
            print("Enter three whole numbers from 1 to 5 in that order.")
        verdict = dict(zip(DIMENSIONS, map(int, scores), strict=True))
        result = command(path, dict(action="large-review-verdict", blind=blind, digest=checksum, verdict=verdict))
        if result.get("ok") is not True:
            raise ValueError(f"Could not record the grade ({result.get('reason', 'missing acknowledgement')})")
        print(f"Recorded sample {position} with scores {' '.join(scores)}.\n", flush=True)
    print(f"Recorded {len(cases)} blinded campaign verdicts.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--socket", type=Path, required=True)
    parser.add_argument("samples", nargs="+", metavar="CASE=BLIND_ID")
    args = parser.parse_args()
    if not sys.stdin.isatty() or not sys.stdout.isatty():
        parser.error("Run in a local interactive terminal")
    try:
        selections = dict(item.split("=", 1) for item in args.samples)
    except ValueError:
        parser.error("Provide a case and blind ID for each sample")
    if len(selections) != len(args.samples) or not selections.keys() <= set(CAMPAIGNS):
        parser.error("Select distinct frozen campaign cases")
    try:
        review(args.socket, selections)
    except (EOFError, OSError, ValueError) as error:
        parser.exit(1, f"{error}\n")


if __name__ == "__main__":
    main()
