"""Coding qualification fixtures use bounded read-only SQL over synthetic data."""
import unittest

from fixtures.chat_coding import evaluate, MOE_TASKS, TASKS


class CodingFixtureTests(unittest.TestCase):
    def test_known_solutions(self):
        solutions = (
            "SELECT region, SUM(units) FROM orders GROUP BY region ORDER BY region",
            "SELECT region FROM orders WHERE units >= 5 GROUP BY region ORDER BY region",
        )
        for task, solution in zip(TASKS, solutions, strict=True):
            self.assertTrue(evaluate(task, solution))
            self.assertTrue(evaluate(task, f"```sql\n{solution}\n```"))

    def test_large_model_holdouts_require_correct_results_on_both_tables(self):
        count, maximum = MOE_TASKS
        self.assertTrue(evaluate(count, "SELECT region, COUNT(*) FROM orders GROUP BY region "
                                        "HAVING COUNT(*) >= 2 ORDER BY region"))
        self.assertTrue(evaluate(maximum, "SELECT region, MAX(units) FROM orders "
                                          "GROUP BY region ORDER BY region"))
        self.assertFalse(evaluate(count, "SELECT region, COUNT(*) FROM orders GROUP BY region"))
        self.assertFalse(evaluate(maximum, "SELECT region, SUM(units) FROM orders "
                                           "GROUP BY region ORDER BY region"))

    def test_wrong_or_unbounded_sql_fails_even_with_expected_rows(self):
        task = TASKS[0]
        for sql in (
            "SELECT region, units FROM orders",
            "SELECT 'east',9 UNION ALL SELECT 'north',2 UNION ALL SELECT 'west',5",
            "SELECT region, SUM(units) FROM orders GROUP BY region; DELETE FROM orders",
            "PRAGMA table_info(orders)",
            "SELECT load_extension('does-not-exist')",
            "WITH RECURSIVE x(n) AS (VALUES(1) UNION ALL SELECT n+1 FROM x) SELECT max(n) FROM x",
            "```sql\nSELECT region, SUM(units) FROM orders GROUP BY region; DELETE FROM orders\n```",
            "Here is the query.\n```sql\nSELECT region, SUM(units) FROM orders GROUP BY region\n```",
        ):
            with self.subTest(sql=sql):
                self.assertFalse(evaluate(task, sql))
