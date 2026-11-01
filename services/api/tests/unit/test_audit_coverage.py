"""Everything that changes the memory, its settings, or sends the owner's data to a model leaves an audit event;
the owner's words never do, and dropping old events is itself recorded."""

from datetime import datetime, timedelta

import pytest

from recall_api.application.audit import Auditor
from recall_api.application.transcribe_speech import TranscribeSpeech
from recall_api.application.trust import TrustPolicy
from recall_api.domain.audit import Action, Actor, AuditEvent, Outcome
from recall_api.domain.memory import Trust
from tests.fakes import FixedClock


class Log:
    def __init__(self) -> None:
        self.events = []

    def record(self, event):
        self.events.append(event)

    def prune(self, before):
        old = [e for e in self.events if e.at < before]
        self.events = [e for e in self.events if e.at >= before]
        return len(old)


def _auditor(log: Log, days: int = 90) -> Auditor:
    n = iter(range(1000))
    return Auditor(log, FixedClock(), lambda prefix: f"{prefix}{next(n)}", days)


class Words:
    def __init__(self, text: str | None = None) -> None:
        self.text = text

    def transcribe(self, audio, content_type):
        if self.text is None:
            raise RuntimeError("Muse Voice Transcribe is unreachable")
        return self.text


def test_audio_leaving_the_mac_is_recorded_without_the_words():
    log = Log()
    t = TranscribeSpeech(Words("where are my reading glasses"), _auditor(log))("x" * 2048, "audio/m4a")
    assert t.text == "where are my reading glasses"
    (e,) = log.events
    assert (e.action, e.actor, e.outcome) == (Action.VOICE_TRANSCRIBED, Actor.OWNER, Outcome.OK)
    assert e.detail["bytes"] == 2048 and e.detail["words"] == 5 and e.detail["model"] == "muse-voice-transcribe-1.0"
    assert "glasses" not in str(e.detail)


def test_a_transcription_that_fails_is_recorded_as_failed():
    log = Log()
    with pytest.raises(RuntimeError):
        TranscribeSpeech(Words(None), _auditor(log))(b"x", "audio/m4a")
    assert log.events[0].outcome == Outcome.FAILED and log.events[0].detail["why"] == "RuntimeError"


def test_changing_the_trust_level_is_recorded_with_what_it_was():
    log, values = Log(), {}
    store = type("S", (), {"get": lambda s, k: values.get(k), "put": lambda s, k, v: values.__setitem__(k, v)})()
    TrustPolicy(store, _auditor(log)).set(Trust.CAREFUL)
    (e,) = log.events
    assert e.action == Action.TRUST_CHANGED and e.detail == {"level": "careful", "was": "balanced"}


def test_dropping_old_events_leaves_a_record_of_how_many_and_up_to_when():
    log = Log()
    auditor = _auditor(log, days=30)
    old = FixedClock().now() - timedelta(days=40)
    log.record(AuditEvent("old", old, Actor.ROBOT, Action.HOME_MEMORY_QUERY, Outcome.OK))
    assert auditor.prune() == 1
    (e,) = log.events
    assert (e.action, e.actor, e.detail["dropped"]) == (Action.AUDIT_PRUNED, Actor.SYSTEM, 1)
    assert datetime.fromisoformat(e.detail["before"]) == FixedClock().now() - timedelta(days=30)
    assert auditor.prune() == 0 and len(log.events) == 1  # nothing to drop: nothing recorded


def test_an_upload_is_recorded_when_it_starts_and_when_its_checksum_fails():
    import hashlib

    from recall_api.application.upload_scan import UploadScan
    from tests.fakes import MemoryBlobs, MemoryRepo, MemoryUnpacker, RecordingTrigger
    from tests.unit.test_upload_scan import PART, SCAN, parts, setup

    _, _, archive, manifest = setup()
    blobs, log = MemoryBlobs(), Log()
    up = UploadScan(MemoryRepo(), MemoryRepo(), blobs, MemoryUnpacker(blobs), RecordingTrigger(), FixedClock(),
                    audit=_auditor(log))  # fmt: skip
    up.create(SCAN, "flat", "Living room", len(archive), "0" * 64, PART)  # the phone claimed another archive
    for n, p in enumerate(parts(archive), 1):
        up.put_part(SCAN, n, p, hashlib.sha256(p).hexdigest())
    up.put_manifest(SCAN, manifest)
    assert up.complete(SCAN).status.value == "failed"
    assert [(e.action, e.outcome) for e in log.events] == [
        (Action.SCAN_CREATED, Outcome.OK),
        (Action.SCAN_UPLOADED, Outcome.FAILED),
    ]
    assert "checksum" in log.events[1].detail["why"] and log.events[0].detail["room"] == "Living room"
