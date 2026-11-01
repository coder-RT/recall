"""Limits in front of the routers: body sizes (413), calls per minute on the routes that reach a model (429,
audited), zip bombs, results with numbers that aren't finite or labels with control characters, and the bind."""

import io
import json
import zipfile

import pytest
from fastapi.testclient import TestClient

from recall_api.adapters.outbound.storage import zip_unpacker
from recall_api.adapters.outbound.storage.zip_unpacker import ZipEpisodeUnpacker
from recall_api.application.ingest_scan import all_finite
from recall_api.config.settings import Settings
from recall_api.infra.app import create_app
from recall_api.infra.guard import RateLimiter, body_limit, caller_id
from tests.fakes import MemoryBlobs

OWNER = {"Authorization": "Bearer owner"}


def _client(tmp_path) -> TestClient:
    return TestClient(create_app(Settings(RECALL_DATA_DIR=tmp_path, RECALL_DEVICE_KEY="owner", RECALL_TRACES="off")))


class Clock:
    def __init__(self) -> None:
        self.t = 0.0

    def __call__(self) -> float:
        return self.t


def test_each_route_has_its_own_body_limit():
    assert body_limit("PUT", "/scans/s1/parts/3") == 64 * 1024 * 1024
    assert body_limit("POST", "/transcribe") == 10 * 1024 * 1024
    assert body_limit("POST", "/ask") == 1024 * 1024
    assert body_limit("GET", "/scans/s1") == 1024 * 1024


def test_a_body_over_the_limit_is_refused_before_it_is_read(tmp_path):
    big = b"x" * (1024 * 1024 + 1)
    r = _client(tmp_path).post("/ask", content=big, headers={**OWNER, "content-type": "application/json"})
    assert r.status_code == 413 and r.json()["error"] == "too_large"


def test_the_bucket_refills_over_a_minute():
    clock = Clock()
    limiter = RateLimiter(clock=clock)
    assert all(limiter.allow("k", "POST", "/ask")[0] for _ in range(30))
    ok, wait = limiter.allow("k", "POST", "/ask")
    assert not ok and wait >= 1
    assert limiter.allow("other", "POST", "/ask")[0]  # each key has its own bucket
    assert limiter.allow("k", "GET", "/scans/s1")[0]  # reads are never limited
    clock.t += 2.0  # one call's worth back (30 a minute)
    assert limiter.allow("k", "POST", "/ask")[0]


def test_the_limiter_forgets_the_oldest_keys_first():
    limiter = RateLimiter(clock=Clock(), max_buckets=3)
    for who in "abcd":
        limiter.allow(who, "POST", "/ask")
    assert [k[0] for k in limiter._buckets] == ["b", "c", "d"]


def test_too_many_questions_get_429_and_an_audit_event(tmp_path):
    client = _client(tmp_path)
    codes = [client.post("/scans/x/complete", headers=OWNER).status_code for _ in range(11)]
    assert codes[-1] == 429 and 429 not in codes[:10]
    r = client.post("/scans/x/complete", headers=OWNER)
    assert r.json()["error"] == "rate_limited" and int(r.headers["retry-after"]) >= 1
    events = client.get("/audit", params={"action": "rate.limited"}, headers=OWNER).json()
    assert events and events[0]["outcome"] == "refused" and "owner" not in json.dumps(events)


def test_the_key_is_counted_by_its_hash_never_itself():
    assert "owner" not in caller_id("Bearer owner", "1.2.3.4") and caller_id(None, "1.2.3.4") == "ip:1.2.3.4"


def _zip(files: dict[str, bytes]) -> bytes:
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
        for name, data in files.items():
            z.writestr(name, data)
    return buf.getvalue()


def test_a_zip_bomb_is_refused_before_it_is_unpacked(monkeypatch):
    blobs = MemoryBlobs()
    blobs.put("a.zip", _zip({"frames/0.jpg": b"\0" * 5000}))
    monkeypatch.setattr(zip_unpacker, "MAX_UNPACKED", 4000)
    with pytest.raises(ValueError, match="too large"):
        ZipEpisodeUnpacker(blobs).unpack("a.zip", "ep")
    assert not [k for k in blobs.data if k.startswith("ep/")]
    monkeypatch.setattr(zip_unpacker, "MAX_UNPACKED", 10**9)
    monkeypatch.setattr(zip_unpacker, "MAX_ENTRIES", 2)
    blobs.put("b.zip", _zip({"a": b"1", "b": b"2", "c": b"3"}))
    with pytest.raises(ValueError):
        ZipEpisodeUnpacker(blobs).unpack("b.zip", "ep")


def test_numbers_must_be_finite():
    assert all_finite({"objects": [{"centroid": [1.0, 2.0, 0.5]}], "n": 3})
    assert not all_finite({"objects": [{"centroid": [1.0, float("nan"), 0.5]}]})
    assert not all_finite([float("inf")])


def test_a_result_with_nan_or_a_control_character_in_a_label_is_refused(tmp_path):
    client = _client(tmp_path)
    thing = {"label": "mug", "centroid": [1, 1, 0.8], "bbox_min": [0.9, 0.9, 0.7], "bbox_max": [1.1, 1.1, 0.9],
             "confidence": 0.9, "sightings": 3}  # fmt: skip
    room = {"floor_polygon": [[0, 0], [4, 0], [4, 3], [0, 3]], "walls": [], "furniture": [], "height_m": 2.5}
    base = {
        "scan_id": "0b9f2a1e-0000-4000-8000-000000000009",
        "room": room,
        "landmarks": [],
        "objects": [thing],
        "stats": {},
    }
    nan = json.dumps({**base, "objects": [{**thing, "centroid": [1, float("nan"), 0.8]}]})
    r = client.post("/scans/s1/results", content=nan, headers={**OWNER, "content-type": "application/json"})
    assert r.status_code == 422 and "finite" in r.json()["detail"]
    bad = {**base, "objects": [{**thing, "label": "mug\u001b[2J"}]}
    r = client.post("/scans/s1/results", json=bad, headers=OWNER)
    assert r.status_code == 422 and "label" in r.json()["detail"]


def test_the_api_listens_on_loopback_unless_asked(monkeypatch):
    from recall_api.infra import app as app_module

    seen = {}
    monkeypatch.setattr(app_module.uvicorn, "run", lambda *a, **k: seen.update(k))
    monkeypatch.delenv("RECALL_BIND_HOST", raising=False)
    app_module.main()
    assert seen["host"] == "127.0.0.1"
    monkeypatch.setenv("RECALL_BIND_HOST", "0.0.0.0")
    app_module.main()
    assert seen["host"] == "0.0.0.0"
