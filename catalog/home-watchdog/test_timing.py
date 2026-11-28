import runpy
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import patch


is_late = runpy.run_path(str(Path(__file__).with_name("timing.py")))["is_late"]
INTERVAL = timedelta(minutes=15)


def utc(hour: int, minute: int, second: int = 0) -> datetime:
    return datetime(2030, 1, 2, hour, minute, second, tzinfo=timezone.utc)


class TimingTests(unittest.TestCase):
    def test_interval_requires_more_than_two_intervals(self):
        cases = (
            ("before", utc(10, 29, 59), utc(10, 0), INTERVAL, False),
            ("exactly at", utc(10, 30), utc(10, 0), INTERVAL, False),
            ("after", utc(10, 30, 1), utc(10, 0), INTERVAL, True),
            ("never completed", utc(10, 0), None, INTERVAL, True),
            ("longer interval at deadline", utc(11, 30), utc(10, 0), timedelta(minutes=45), False),
            ("shorter interval past deadline", utc(10, 5), utc(10, 0), timedelta(minutes=2), True),
        )
        for name, now, last_completed, interval, expected in cases:
            with self.subTest(case=name):
                self.assertIs(is_late(now, last_completed, interval), expected)

    def test_fixed_time_requires_a_completion_at_or_after_due(self):
        due_at = utc(9, 0)
        cases = (
            ("before grace ends", utc(9, 29, 59), None, False),
            ("exactly at grace end", utc(9, 30), None, False),
            ("after grace ends", utc(9, 30, 1), None, True),
            ("completed before due", utc(9, 30, 1), utc(8, 59, 59), True),
            ("completed at due", utc(9, 30, 1), utc(9, 0), False),
            ("completed during grace", utc(9, 30, 1), utc(9, 15), False),
            ("completed at grace end", utc(9, 30, 1), utc(9, 30), False),
        )
        for name, now, last_completed, expected in cases:
            with self.subTest(case=name):
                self.assertIs(is_late(now, last_completed, due_at), expected)

    def test_t3_failure_overrides_timing_but_success_does_not(self):
        cases = (
            ("failed with a fresh interval completion", utc(10, 29), utc(10, 0), INTERVAL, "failed", True),
            ("failed with a fresh fixed-time completion", utc(9, 10), utc(9, 5), utc(9, 0), "failed", True),
            ("succeeded with a fresh completion", utc(10, 29), utc(10, 0), INTERVAL, "succeeded", False),
            ("succeeded with a stale completion", utc(10, 31), utc(10, 0), INTERVAL, "succeeded", True),
            ("succeeded without an interval completion", utc(10, 0), None, INTERVAL, "succeeded", True),
            ("succeeded without a due completion", utc(9, 31), None, utc(9, 0), "succeeded", True),
        )
        for name, now, last_completed, schedule, status, expected in cases:
            with self.subTest(case=name):
                self.assertIs(is_late(now, last_completed, schedule, last_run_status=status), expected)

    def test_decision_uses_only_its_inputs(self):
        with (
            patch("builtins.open", side_effect=AssertionError("opened a file")),
            patch("io.open", side_effect=AssertionError("opened a file")),
            patch("os.open", side_effect=AssertionError("opened a file")),
            patch("socket.socket", side_effect=AssertionError("opened a socket")),
            patch("subprocess.Popen", side_effect=AssertionError("started a command")),
        ):
            for _ in range(2):
                self.assertIs(is_late(utc(10, 30, 1), utc(10, 0), INTERVAL), True)
                self.assertIs(is_late(utc(9, 29), None, utc(9, 0)), False)


if __name__ == "__main__":
    unittest.main()
