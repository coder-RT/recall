"""When something was seen, said the way a person says it, in the home's own time zone ("yesterday at 04:21")."""

from __future__ import annotations

from datetime import datetime
from zoneinfo import ZoneInfo

_DAYS = ("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday")
_MONTHS = ("January", "February", "March", "April", "May", "June", "July", "August", "September", "October",
           "November", "December")  # fmt: skip


def spoken_when(seen: datetime, now: datetime, tz: ZoneInfo) -> str:
    """Recent sightings as "how long ago"; older ones by day and local time, so a bare hour never stands alone."""
    minutes = max(0, int((now - seen).total_seconds() // 60))
    if minutes < 1:
        return "just now"
    if minutes < 60:
        return "1 minute ago" if minutes == 1 else f"{minutes} minutes ago"
    if minutes < 24 * 60:
        hours = round(minutes / 60)
        return "about 1 hour ago" if hours == 1 else f"about {hours} hours ago"
    local, today = seen.astimezone(tz), now.astimezone(tz).date()
    days = (today - local.date()).days
    at = local.strftime("%H:%M")
    if days <= 1:
        return f"yesterday at {at}"
    if days < 7:
        return f"on {_DAYS[local.weekday()]} at {at}"
    return f"on {local.day} {_MONTHS[local.month - 1]}"


def is_plural(label: str) -> bool:
    """Good enough for object labels: "keys", "glasses", "headphones" are plural; "glass" and "bus" are not."""
    word = label.strip().split()[-1].lower() if label.strip() else ""
    return word.endswith("s") and not word.endswith(("ss", "us", "is"))
