from datetime import UTC, datetime


class SystemClock:
    def now(self) -> datetime:
        return datetime.now(UTC)


class FrozenClock:
    """Always the same moment: the recorded demo runs at the time it was recorded."""

    def __init__(self, at: datetime) -> None:
        self.at = at if at.tzinfo else at.replace(tzinfo=UTC)

    def now(self) -> datetime:
        return self.at
