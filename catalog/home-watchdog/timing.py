from datetime import datetime, timedelta


def is_late(
    now: datetime,
    last_completed: datetime | None,
    interval_or_due: timedelta | datetime,
    *,
    last_run_status: str | None = None,
) -> bool:
    return False
