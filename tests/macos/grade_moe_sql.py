"""Grade only the four frozen read-only SQL fixtures from the private review pages."""

import argparse
import base64
from hashlib import sha256
import json
from pathlib import Path

from backend.enroll import command
from backend.enrollment import Rejected
from fixtures.chat_coding import MOE_TASKS, TASKS, evaluate

CASES = {f"coding-{index}": task for index, task in enumerate((*TASKS, *MOE_TASKS), 1)}


def review_sample(path, blind, case, kind):
    cursor = 0
    chunks = bytearray()
    checksum = None
    while cursor is not None:
        page = command(path, {"action": "large-review-page", "blind": blind, "cursor": cursor})
        if (page.get("ok") is not True or page.get("kind") != kind
                or page.get("blind") != blind or page.get("case") != case):
            raise Rejected("review_output_unavailable")
        if checksum is None:
            checksum = page["digest"]
        if checksum != page["digest"]:
            raise Rejected("review_output_mismatch")
        chunks.extend(base64.b64decode(page["data"], validate=True))
        cursor = page["cursor"]
        if len(chunks) > 64 * 1024 or (cursor is not None and cursor != len(chunks)):
            raise Rejected("invalid_review_frame")
    if sha256(chunks).hexdigest() != checksum:
        raise Rejected("review_output_mismatch")
    return chunks.decode(), checksum


def grade(path, blind, case):
    answer, checksum = review_sample(path, blind, case, "coding")
    return dict(blind=blind, digest=checksum, verdict=evaluate(CASES[case], answer))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--socket", type=Path, required=True)
    parser.add_argument("--blind", required=True)
    parser.add_argument("--case", choices=CASES, required=True)
    args = parser.parse_args()
    try:
        print(json.dumps(grade(args.socket, args.blind, args.case)))
    except (OSError, ValueError) as error:
        parser.exit(1, f"{error}\n")


if __name__ == "__main__":
    main()
