from datetime import UTC, datetime

from recall_api.domain.memory import Scan, ScanStatus
from recall_api.infra.regression import compare


def test_scan_folder_starts_with_the_time_and_room():
    s = Scan(
        "7a736bf2",
        "flat",
        "Living Room!",
        ScanStatus.UPLOADING,
        10,
        "x",
        8,
        datetime(2026, 10, 30, 4, 21, 1, tzinfo=UTC),
    )
    assert s.folder == "scans/2026-10-30T042101Z_living-room_7a736bf2"


def test_regression_compare_reports_shifted_missing_and_new():
    before = {"objects": [{"label": "keys", "centroid": [0, 0, 0.7]}, {"label": "mug", "centroid": [1, 1, 0.8]}]}
    after = {"objects": [{"label": "keys", "centroid": [0.5, 0, 0.7]}, {"label": "bag", "centroid": [2, 2, 0.4]}]}
    diff = compare(before, after)
    assert diff["shifted"] == ["keys 0.50 m"] and diff["missing"] == ["mug"] and diff["new"] == 1
