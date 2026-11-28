"""Reviewed trial recipes and the shared paired transport predicate."""

import re

from .enrollment import Rejected, STUDIOS
from .job_ledger import KEY, TOKEN_LIMIT, integer

ENGINES = ("mlx-lm", "mlx-serve", "exo")
GIB = 1024**3


def digest(value):
    if not isinstance(value, str) or not re.fullmatch(r"[a-f0-9]{64}", value):
        raise Rejected("invalid_digest")
    return value


def recipe_name(value):
    if not isinstance(value, str) or not KEY.fullmatch(value):
        raise Rejected("invalid_recipe")
    return value


def recipes(document):
    if not isinstance(document, dict) or len(document) > 16:
        raise Rejected("invalid_recipe")
    return {recipe_name(name): recipe(value) for name, value in document.items()}


def recipe(value):
    fields = {"candidate", "fixture", "engine", "devices", "tokens", "deadline", "budgets"}
    if not isinstance(value, dict) or value.keys() != fields or value["engine"] not in ENGINES:
        raise Rejected("invalid_recipe")
    budgets, devices = value["budgets"], value["devices"]
    if not isinstance(budgets, dict) or set(budgets) not in ({STUDIOS[0]}, {STUDIOS[1]}, set(STUDIOS)):
        raise Rejected("invalid_recipe")
    if not isinstance(devices, dict) or devices.keys() != budgets.keys():
        raise Rejected("invalid_recipe")
    bounds = {}
    for slot, budget in budgets.items():
        if not isinstance(budget, dict) or budget.keys() != {"ceiling", "floor"}:
            raise Rejected("invalid_recipe")
        bounds[slot] = {key: integer(amount, 1, 256*GIB) for key, amount in budget.items()}
    mapped = {slot: digest(device) for slot, device in devices.items()}
    if len(set(mapped.values())) != len(mapped):
        raise Rejected("invalid_recipe")
    return dict(candidate=digest(value["candidate"]), fixture=digest(value["fixture"]),
                engine=value["engine"], devices=mapped, budgets=bounds,
                tokens=integer(value["tokens"], 1, TOKEN_LIMIT),
                deadline=integer(value["deadline"], 1, 3600))


def trial_measurement(value, *, ceiling, deadline, tokens):
    fields = {"peak_bytes", "first_text_ms", "elapsed_ms", "fixture_passed", "completed_tokens"}
    if (not isinstance(value, dict) or value.keys() != fields
            or type(value["fixture_passed"]) is not bool):
        raise Rejected("invalid_trial_measurement")
    elapsed = integer(value["elapsed_ms"], 1, deadline * 1000)
    integer(value["peak_bytes"], 1, ceiling - 1)
    integer(value["completed_tokens"], 1, tokens)
    integer(value["first_text_ms"], 0, elapsed)
    return value


def transport_observation(value, *, candidate, device, attempt):
    """Bound diagnostic data before persisting it with the authenticated receipt."""
    if (not isinstance(value, dict)
            or value.keys() != {"device", "candidate", "attempt", "transfers"}
            or value["device"] != device or value["candidate"] != candidate
            or value["attempt"] != attempt):
        raise Rejected("transport_identity", 409)
    transfers = value["transfers"]
    if not isinstance(transfers, list) or len(transfers) > 16:
        raise Rejected("invalid_transport")
    seen = set()
    for transfer in transfers:
        if (not isinstance(transfer, dict)
                or transfer.keys() != {"id", "direction", "transport", "count"}
                or not isinstance(transfer["id"], str)
                or not re.fullmatch(r"[a-zA-Z0-9_-]{1,40}", transfer["id"])
                or transfer["direction"] not in ("send", "receive")
                or transfer["transport"] not in ("rdma", "tcp")):
            raise Rejected("invalid_transport")
        integer(transfer["count"], 1, 2**31 - 1)
        key = (transfer["id"], transfer["direction"])
        if key in seen:
            raise Rejected("invalid_transport")
        seen.add(key)
    return value


def paired_rdma(left, right):
    """Both peers must account for every reported forward-pass transfer."""
    def counts(observation, *, reverse=False):
        result = {}
        for transfer in observation["transfers"]:
            direction = transfer["direction"]
            if reverse:
                direction = "receive" if direction == "send" else "send"
            result[(transfer["id"], direction, transfer["transport"])] = transfer["count"]
        return result

    if not left or not right or left["attempt"] != right["attempt"]:
        return False
    expected = counts(left)
    return bool(expected and all(key[2] == "rdma" for key in expected)
                and expected == counts(right, reverse=True))
