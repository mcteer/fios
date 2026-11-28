"""Frozen task prompts and behavioral checks for Studio text qualification."""

from contextlib import closing
from dataclasses import dataclass
import re
import sqlite3


@dataclass(frozen=True)
class Task:
    prompt: str
    expected: tuple
    datasets: tuple | None = None


ORDERS = (
    (("east", 2), ("east", 7), ("north", 2), ("west", 5)),
    (("east", 1), ("east", 5), ("south", 3), ("south", 5), ("west", 9), ("west", 1)),
)

TASKS = (
    Task("Return one SQLite SELECT over orders(region TEXT, units INTEGER) that returns each "
         "region and its total units. Order by region ascending. Return SQL only.",
         ((("east", 9), ("north", 2), ("west", 5)), (("east", 6), ("south", 8), ("west", 10)))),
    Task("Return one SQLite SELECT over orders(region TEXT, units INTEGER) that lists distinct "
         "regions with at least one order of five units or more. Order by region ascending. "
         "Return SQL only.", ((("east",), ("west",)), (("east",), ("south",), ("west",)))),
)


# Separate examples prevent a canned result derived from the original tables.
MOE_ORDERS = (
    (("ash", 0), ("ash", 6), ("elm", 3), ("pine", 8), ("pine", 8)),
    (("birch", 2), ("elm", 3), ("elm", 4), ("spruce", 9)),
)
MOE_TASKS = (
    Task("Return only one SQLite SELECT over orders(region TEXT, units INTEGER). "
         "Return regions with two or more orders and their order counts, in ascending region order.",
         ((("ash", 2), ("pine", 2)), (("elm", 2),)), MOE_ORDERS),
    Task("Return only one SQLite SELECT over orders(region TEXT, units INTEGER). "
         "List each region and the largest single order in it, in ascending region order.",
         ((("ash", 6), ("elm", 3), ("pine", 8)),
          (("birch", 2), ("elm", 4), ("spruce", 9))), MOE_ORDERS),
)


def authorize(action, first, second, _database, _context):
    if action == sqlite3.SQLITE_SELECT:
        return sqlite3.SQLITE_OK
    if action == sqlite3.SQLITE_READ and first == "orders" and second in ("region", "units", ""):
        return sqlite3.SQLITE_OK
    if action == sqlite3.SQLITE_FUNCTION and second in ("sum", "distinct", "count", "max"):
        return sqlite3.SQLITE_OK
    return sqlite3.SQLITE_DENY


def evaluate(task, sql):
    """Evaluate only one read-only query on the fixture, with a VM step limit."""
    if not isinstance(sql, str):
        return False
    try:
        if len(sql.encode()) > 4096:
            return False
        # Chat renders either bare SQL or a single fenced block. Keep the
        # evaluator's SQL restrictions identical for both presentations.
        sql = sql.strip()
        fenced = re.fullmatch(r"```(?:sql|sqlite)?[ \t]*\r?\n([\s\S]+?)\r?\n```", sql, re.IGNORECASE)
        if fenced:
            sql = fenced[1]
        for orders, expected in zip(task.datasets if task.datasets is not None else ORDERS, task.expected, strict=True):
            with closing(sqlite3.connect(":memory:")) as db:
                db.execute("CREATE TABLE orders(region TEXT NOT NULL, units INTEGER NOT NULL)")
                db.executemany("INSERT INTO orders VALUES (?,?)", orders)
                db.execute("PRAGMA query_only=ON")
                db.set_authorizer(authorize)
                db.set_progress_handler(lambda: 1, 20_000)
                actual = db.execute(sql).fetchmany(len(expected) + 1)
                if tuple(actual) != expected:
                    return False
        return True
    except (sqlite3.Error, UnicodeError, ValueError):
        return False
