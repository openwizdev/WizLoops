from datetime import datetime, timedelta


FIXED_TIME_GRACE = timedelta(minutes=30)


def is_late(
    now: datetime,
    last_completed: datetime | None,
    interval_or_due: timedelta | datetime,
    *,
    last_run_status: str | None = None,
) -> bool:
    if last_run_status == "failed":
        return True
    if isinstance(interval_or_due, timedelta):
        return last_completed is None or now - last_completed > 2 * interval_or_due
    due_at = interval_or_due
    return now - due_at > FIXED_TIME_GRACE and (
        last_completed is None or last_completed < due_at
    )
