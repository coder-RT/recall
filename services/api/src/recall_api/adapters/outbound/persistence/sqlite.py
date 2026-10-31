"""SQLite repositories (SQLAlchemy Core, plain SQL). The schema lives in db/migrations."""

from __future__ import annotations

import json
from dataclasses import asdict
from datetime import datetime

from sqlalchemy import Engine, text

from recall_api.application.ports import AnswerRecord
from recall_api.domain.audit import Action, Actor, AuditEvent, Outcome
from recall_api.domain.memory import (
    BBox,
    Corrections,
    Home,
    Landmark,
    Observation,
    Position,
    RoomModel,
    Scan,
    ScanChange,
    ScanStatus,
    SetAside,
    TrackedObject,
)


def _pos(v: str) -> Position:
    x, y, z = json.loads(v)
    return Position(x, y, z)


class SqliteHomes:
    def __init__(self, engine: Engine) -> None:
        self.engine = engine

    def get(self, home_id: str) -> Home | None:
        with self.engine.connect() as c:
            row = c.execute(text("SELECT * FROM homes WHERE id = :id"), {"id": home_id}).mappings().first()
            if row is None:
                return None
            lms = c.execute(text("SELECT * FROM landmarks WHERE home_id = :id"), {"id": home_id}).mappings().all()
        landmarks = [
            Landmark(
                id=r["id"],
                label=r["label"],
                bbox=BBox(_pos(r["bbox_min"]), _pos(r["bbox_max"])),
                centroid=_pos(r["centroid"]),
                room=r["room"],
                front_dir=tuple(json.loads(r["front_dir"])) if r["front_dir"] else None,
            )
            for r in lms
        ]
        room = RoomModel.from_dict(json.loads(row["room_model"])) if row["room_model"] else None
        return Home(
            id=row["id"], name=row["name"], room_model=room, landmarks=landmarks, first_scan_id=row["first_scan_id"]
        )

    def save(self, home: Home) -> None:
        with self.engine.begin() as c:
            c.execute(
                text("""
                INSERT INTO homes (id, name, room_model, first_scan_id) VALUES (:id, :name, :room, :first)
                ON CONFLICT(id) DO UPDATE SET name = :name, room_model = :room, first_scan_id = :first"""),
                {
                    "id": home.id,
                    "name": home.name,
                    "first": home.first_scan_id,
                    "room": json.dumps(home.room_model.to_dict()) if home.room_model else None,
                },
            )
            c.execute(text("DELETE FROM landmarks WHERE home_id = :id"), {"id": home.id})
            for lm in home.landmarks:
                c.execute(
                    text("""INSERT INTO landmarks (id, home_id, label, bbox_min, bbox_max, centroid, room, front_dir)
                                  VALUES (:id, :home, :label, :lo, :hi, :c, :room, :front)"""),
                    {
                        "id": lm.id,
                        "home": home.id,
                        "label": lm.label,
                        "lo": json.dumps(lm.bbox.lo.as_tuple()),
                        "hi": json.dumps(lm.bbox.hi.as_tuple()),
                        "c": json.dumps(lm.centroid.as_tuple()),
                        "room": lm.room,
                        "front": json.dumps(lm.front_dir) if lm.front_dir else None,
                    },
                )


class SqliteScans:
    def __init__(self, engine: Engine) -> None:
        self.engine = engine

    @staticmethod
    def _row(r) -> Scan:
        return Scan(
            id=r["id"],
            home_id=r["home_id"],
            room=r["room"],
            status=ScanStatus(r["status"]),
            archive_size=r["archive_size"],
            archive_sha256=r["archive_sha256"],
            part_size=r["part_size"],
            created_at=datetime.fromisoformat(r["created_at"]),
            detail=r["detail"],
            frame_count=r["frame_count"],
            object_count=r["object_count"],
            transform_to_home=tuple(json.loads(r["transform_to_home"])) if r["transform_to_home"] else None,
            aligned_to=r["aligned_to"],
            fresh=bool(r["fresh"]),
            changes=[ScanChange(**c) for c in json.loads(r["changes"] or "[]")],
            provenance=json.loads(r["provenance"]) if r["provenance"] else None,
        )

    def get(self, scan_id: str) -> Scan | None:
        with self.engine.connect() as c:
            r = c.execute(text("SELECT * FROM scans WHERE id = :id"), {"id": scan_id}).mappings().first()
        return self._row(r) if r else None

    def list_for_home(self, home_id: str) -> list[Scan]:
        with self.engine.connect() as c:
            rows = c.execute(text("SELECT * FROM scans WHERE home_id = :h ORDER BY created_at"), {"h": home_id})
            return [self._row(r) for r in rows.mappings().all()]

    def save(self, s: Scan) -> None:
        p = {
            "id": s.id,
            "home": s.home_id,
            "room": s.room,
            "created": s.created_at.isoformat(),
            "status": s.status.value,
            "detail": s.detail,
            "size": s.archive_size,
            "sha": s.archive_sha256,
            "part": s.part_size,
            "frames": s.frame_count,
            "objects": s.object_count,
            "t": json.dumps(s.transform_to_home) if s.transform_to_home else None,
            "aligned": s.aligned_to,
            "fresh": int(s.fresh),
            "changes": json.dumps([asdict(c) for c in s.changes]),
            "prov": json.dumps(s.provenance) if s.provenance else None,
        }
        with self.engine.begin() as c:
            c.execute(
                text("""
                INSERT INTO scans (id, home_id, room, created_at, status, detail, archive_size, archive_sha256,
                                   part_size, frame_count, object_count, transform_to_home, aligned_to, fresh, changes,
                                   provenance)
                VALUES (:id, :home, :room, :created, :status, :detail, :size, :sha, :part, :frames, :objects, :t,
                        :aligned, :fresh, :changes, :prov)
                ON CONFLICT(id) DO UPDATE SET status = :status, detail = :detail, frame_count = :frames,
                    object_count = :objects, transform_to_home = :t, aligned_to = :aligned, fresh = :fresh,
                    changes = :changes, provenance = :prov"""),
                p,
            )

    def delete(self, scan_id: str) -> None:
        with self.engine.begin() as c:
            c.execute(text("DELETE FROM keyframes WHERE scan_id = :id"), {"id": scan_id})
            c.execute(text("DELETE FROM scans WHERE id = :id"), {"id": scan_id})


class SqliteObjects:
    def __init__(self, engine: Engine) -> None:
        self.engine = engine

    def _load(self, c, rows) -> list[TrackedObject]:
        out = []
        for r in rows:
            obs = c.execute(text("SELECT * FROM observations WHERE object_id = :id ORDER BY ts"), {"id": r["id"]})
            out.append(
                TrackedObject(
                    id=r["id"],
                    home_id=r["home_id"],
                    label=r["label"],
                    aliases=tuple(json.loads(r["aliases"])),
                    color=r["color"],
                    size_m=tuple(json.loads(r["size_m"])) if r["size_m"] else None,
                    corrections=Corrections(
                        name=r["user_name"],
                        color=r["user_color"],
                        height_m=r["user_height_m"],
                        note=r["user_note"],
                        confirmed=bool(r["confirmed"]),
                    ),
                    observations=[
                        Observation(
                            id=o["id"],
                            object_id=o["object_id"],
                            scan_id=o["scan_id"],
                            seen_at=datetime.fromisoformat(o["ts"]),
                            position=Position(o["x"], o["y"], o["z"]),
                            confidence=o["confidence"],
                            keyframe_index=o["keyframe_index"],
                            box=tuple(json.loads(o["box"])) if o["box"] else None,
                        )
                        for o in obs.mappings().all()
                    ],
                    set_asides=[
                        SetAside(
                            a["id"],
                            a["scan_id"],
                            a["reason"],
                            datetime.fromisoformat(a["at"]),
                            tuple(json.loads(a["observation_ids"])),
                        )
                        for a in c.execute(
                            text("SELECT * FROM set_asides WHERE object_id = :id ORDER BY at"), {"id": r["id"]}
                        )
                        .mappings()
                        .all()
                    ],  # fmt: skip
                )
            )
        return out

    def list_for_home(self, home_id: str) -> list[TrackedObject]:
        with self.engine.connect() as c:
            rows = c.execute(text("SELECT * FROM objects WHERE home_id = :h ORDER BY label"), {"h": home_id})
            return self._load(c, rows.mappings().all())

    def get(self, object_id: str) -> TrackedObject | None:
        with self.engine.connect() as c:
            rows = c.execute(text("SELECT * FROM objects WHERE id = :id"), {"id": object_id}).mappings().all()
            found = self._load(c, rows)
        return found[0] if found else None

    def get_by_observation(self, observation_id: str) -> TrackedObject | None:
        with self.engine.connect() as c:
            oid = c.execute(text("SELECT object_id FROM observations WHERE id = :id"), {"id": observation_id}).scalar()
        return self.get(oid) if oid else None

    def delete(self, object_id: str) -> None:
        with self.engine.begin() as c:
            c.execute(text("DELETE FROM set_asides WHERE object_id = :id"), {"id": object_id})
            c.execute(text("DELETE FROM observations WHERE object_id = :id"), {"id": object_id})
            c.execute(text("DELETE FROM objects WHERE id = :id"), {"id": object_id})

    def save(self, obj: TrackedObject) -> None:
        with self.engine.begin() as c:
            c.execute(
                text("""INSERT INTO objects (id, home_id, label, aliases, color, size_m, user_name, user_color,
                                                user_height_m, user_note, confirmed)
                        VALUES (:id, :h, :l, :a, :color, :size, :un, :uc, :uh, :note, :ok)
                        ON CONFLICT(id) DO UPDATE SET label = :l, aliases = :a, color = :color, size_m = :size,
                            user_name = :un, user_color = :uc, user_height_m = :uh, user_note = :note,
                            confirmed = :ok"""),
                {
                    "id": obj.id,
                    "h": obj.home_id,
                    "l": obj.label,
                    "a": json.dumps(list(obj.aliases)),
                    "color": obj.color,
                    "size": json.dumps(list(obj.size_m)) if obj.size_m else None,
                    "un": obj.corrections.name,
                    "uc": obj.corrections.color,
                    "uh": obj.corrections.height_m,
                    "note": obj.corrections.note,
                    "ok": int(obj.corrections.confirmed),
                },
            )
            for o in obj.observations:
                c.execute(
                    text("""
                    INSERT INTO observations (id, object_id, scan_id, keyframe_index, ts, x, y, z, confidence, box)
                    VALUES (:id, :obj, :scan, :kf, :ts, :x, :y, :z, :conf, :box)
                    ON CONFLICT(id) DO NOTHING"""),
                    {
                        "id": o.id,
                        "obj": obj.id,
                        "scan": o.scan_id,
                        "kf": o.keyframe_index,
                        "ts": o.seen_at.isoformat(),
                        "x": o.position.x,
                        "y": o.position.y,
                        "z": o.position.z,
                        "conf": o.confidence,
                        "box": json.dumps([round(v, 1) for v in o.box]) if o.box else None,
                    },
                )
            for a in obj.set_asides:
                c.execute(
                    text("""INSERT INTO set_asides (id, object_id, scan_id, reason, at, observation_ids)
                            VALUES (:id, :obj, :scan, :reason, :at, :ids) ON CONFLICT(id) DO NOTHING"""),
                    {"id": a.id, "obj": obj.id, "scan": a.scan_id, "reason": a.reason, "at": a.at.isoformat(),
                     "ids": json.dumps(list(a.observation_ids))},
                )  # fmt: skip
            # erasing a scan (the privacy exception) is the only way a sighting or set-aside leaves the aggregate
            keep_a = [a.id for a in obj.set_asides]
            marks_a = ", ".join(f":a{i}" for i in range(len(keep_a))) or "''"
            c.execute(
                text(f"DELETE FROM set_asides WHERE object_id = :id AND id NOT IN ({marks_a})"),
                {"id": obj.id, **{f"a{i}": k for i, k in enumerate(keep_a)}},
            )
            # the aggregate is the truth: sightings it no longer holds (an erased scan's) go
            keep = [o.id for o in obj.observations]
            marks = ", ".join(f":k{i}" for i in range(len(keep))) or "''"
            c.execute(
                text(f"DELETE FROM observations WHERE object_id = :id AND id NOT IN ({marks})"),
                {"id": obj.id, **{f"k{i}": k for i, k in enumerate(keep)}},
            )


class SqliteAnswerLog:
    """Append-only (a trigger refuses updates): every answer, its steps and the sightings behind it."""

    def __init__(self, engine: Engine) -> None:
        self.engine = engine

    def record(self, a: AnswerRecord) -> None:
        with self.engine.begin() as c:
            c.execute(
                text("""INSERT INTO answer_log (id, home_id, created_at, question, text, grounded, object_id, steps,
                                                observation_ids, provider, model, prompt_tokens, completion_tokens,
                                                latency_ms)
                        VALUES (:id, :home, :at, :q, :text, :g, :obj, :steps, :obs, :prov, :model, :pt, :ct, :ms)"""),
                {"id": a.id, "home": a.home_id, "at": a.created_at.isoformat(), "q": a.question, "text": a.text,
                 "g": int(a.grounded), "obj": a.object_id, "steps": json.dumps(a.steps, default=str),
                 "obs": json.dumps(a.observation_ids), "prov": a.provider, "model": a.model, "pt": a.prompt_tokens,
                 "ct": a.completion_tokens, "ms": a.latency_ms},
            )  # fmt: skip

    @staticmethod
    def _row(r) -> AnswerRecord:
        return AnswerRecord(
            r["id"], r["home_id"], datetime.fromisoformat(r["created_at"]), r["question"], r["text"],
            bool(r["grounded"]), r["object_id"], json.loads(r["steps"]), json.loads(r["observation_ids"]),
            r["provider"], r["model"], r["prompt_tokens"], r["completion_tokens"], r["latency_ms"],
        )  # fmt: skip

    def get(self, answer_id: str) -> AnswerRecord | None:
        with self.engine.connect() as c:
            r = c.execute(text("SELECT * FROM answer_log WHERE id = :id"), {"id": answer_id}).mappings().first()
        return self._row(r) if r else None

    def recent(self, home_id: str, limit: int = 100) -> list[AnswerRecord]:
        with self.engine.connect() as c:
            rows = (
                c.execute(
                    text("SELECT * FROM answer_log WHERE home_id = :h ORDER BY created_at DESC LIMIT :n"),
                    {"h": home_id, "n": limit},
                )
                .mappings()
                .all()
            )
        return [self._row(r) for r in rows]


class SqliteOwnerSettings:
    def __init__(self, engine: Engine) -> None:
        self.engine = engine

    def get(self, key: str) -> str | None:
        with self.engine.connect() as c:
            return c.execute(text("SELECT value FROM owner_settings WHERE key = :k"), {"k": key}).scalar()

    def put(self, key: str, value: str) -> None:
        with self.engine.begin() as c:
            c.execute(
                text(
                    "INSERT INTO owner_settings (key, value) VALUES (:k, :v) ON CONFLICT(key) DO UPDATE SET value = :v"
                ),
                {"k": key, "v": value},
            )


class SqliteAuditLog:
    """Append-only audit events; the newest first when read."""

    def __init__(self, engine: Engine) -> None:
        self.engine = engine

    def record(self, e: AuditEvent) -> None:
        with self.engine.begin() as c:
            c.execute(
                text("""INSERT INTO audit_events
                        (id, at, actor, action, outcome, target_type, target_id, detail, request_id)
                        VALUES (:id, :at, :actor, :action, :outcome, :tt, :ti, :detail, :rid)"""),
                {"id": e.id, "at": e.at.isoformat(), "actor": e.actor.value, "action": e.action.value,
                 "outcome": e.outcome.value, "tt": e.target_type, "ti": e.target_id, "detail": json.dumps(e.detail),
                 "rid": e.request_id},
            )  # fmt: skip

    def recent(self, limit=50, action=None, actor=None, since=None) -> list[AuditEvent]:
        where, p = [], {"limit": max(1, min(int(limit), 500))}
        if action:
            where.append("action = :action")
            p["action"] = action
        if actor:
            where.append("actor = :actor")
            p["actor"] = actor
        if since:
            where.append("at >= :since")
            p["since"] = since.isoformat()
        sql = "SELECT * FROM audit_events" + (" WHERE " + " AND ".join(where) if where else "")
        with self.engine.connect() as c:
            rows = c.execute(text(sql + " ORDER BY at DESC, id DESC LIMIT :limit"), p).mappings().all()
        return [
            AuditEvent(r["id"], datetime.fromisoformat(r["at"]), Actor(r["actor"]), Action(r["action"]),
                       Outcome(r["outcome"]), r["target_type"], r["target_id"], json.loads(r["detail"]),
                       r["request_id"])
            for r in rows
        ]  # fmt: skip

    def prune(self, before: datetime) -> int:
        with self.engine.begin() as c:
            return c.execute(text("DELETE FROM audit_events WHERE at < :b"), {"b": before.isoformat()}).rowcount
