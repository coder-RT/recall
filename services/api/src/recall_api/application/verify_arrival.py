"""The Verifier: on arrival, one camera frame says whether the thing is really there.

SAM 3.1 finds it in the photo, the LiDAR depth puts it in the home, and geometry decides with the 30 cm rule. Muse
Spark 1.1 is asked only when SAM was unsure, and may only downgrade a confirmation to "uncertain", never confirm.
What the camera saw updates memory (this is an API use case, so the one-writer rule holds): seen where remembered
refreshes the sighting; seen nearby moves it.
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from recall_api.application.audit import NoAudit
from recall_api.application.plan_guidance import GuidanceError, PlanGuidance
from recall_api.application.ports import Clock, Segmenter, VisionProvider
from recall_api.domain.assistant import is_plural
from recall_api.domain.audit import Action, Actor
from recall_api.domain.memory import Observation, Position
from recall_api.domain.ports import TrackedObjectRepository
from recall_api.domain.spatial import CameraView, clock_and_distance, lift_box

SAME_PLACE_M = 0.30  # the 30 cm rule
NEARBY_M = 2.0  # further than this is another one, not ours
MIN_SCORE, SURE_SCORE, HINT_SCORE = 0.5, 0.7, 0.3


@dataclass(frozen=True)
class Verification:
    outcome: str  # confirmed | found_nearby | uncertain | not_here
    say: str
    distance_cm: float | None = None
    sam_score: float | None = None
    position: list[float] | None = None


def _metres(m: float) -> str:
    if m < 1:
        return f"{max(10, int(round(m * 10)) * 10)} centimetres"
    r = round(m * 2) / 2
    return "1 metre" if r == 1 else (f"{int(r)} metres" if r == int(r) else f"{r:.1f} metres")


class VerifyArrival:
    def __init__(
        self,
        guidance: PlanGuidance,
        objects: TrackedObjectRepository,
        segmenter: Segmenter,
        vision: VisionProvider | None,
        clock: Clock,
        new_id,
        audit=None,
    ) -> None:
        self.guidance, self.objects, self.segmenter, self.vision = guidance, objects, segmenter, vision
        self.clock, self.new_id = clock, new_id
        self.audit = audit or NoAudit()

    def __call__(self, session_id: str, jpeg: bytes, view: CameraView) -> Verification:
        v = self._check(session_id, jpeg, view)
        session = self.guidance.sessions.get(session_id)
        self.audit(Action.ARRIVAL_VERIFIED, Actor.OWNER, target_type="object",
                   target_id=session.object_id if session else None, result=v.outcome, distance_cm=v.distance_cm,
                   sam_score=v.sam_score, memory_updated=v.outcome in ("confirmed", "found_nearby"))  # fmt: skip
        return v

    def _check(self, session_id: str, jpeg: bytes, view: CameraView) -> Verification:
        session = self.guidance.sessions.get(session_id)
        if session is None:
            raise GuidanceError("unknown_session", "No such guidance session.")
        obj = self.objects.get(session.object_id)
        last = obj.where() if obj else None
        if last is None:
            raise GuidanceError("object_not_seen", "That object isn't in memory.")
        T, _ = self.guidance._transform(session.home_id)
        name = obj.corrections.name or " ".join(x for x in (obj.display_color(), obj.label) if x)
        verb = "are" if is_plural(name) else "is"
        remembered = np.array(last.position.as_tuple())
        cam_home = T @ view.pose

        masks = [m for m in self.segmenter.segment(jpeg, [obj.label]) if m.box is not None]
        sightings = []
        for m in masks:
            if m.score < HINT_SCORE:
                continue
            world = lift_box(view, m.box)
            if world is not None:
                home = (T @ np.append(world, 1.0))[:3]
                sightings.append((float(np.linalg.norm(home - remembered)), m.score, home))
        sure = [s for s in sightings if s[1] >= MIN_SCORE]
        if not sure:
            if sightings:
                hint = round(max(s[1] for s in sightings), 2)
                return Verification("uncertain", f"I might see your {name}, but I'm not sure. Feel around in front "
                                    "of you, or move the phone slowly.", sam_score=hint)  # fmt: skip
            return Verification("not_here", f"I can't see your {name} from here. It may have moved. Point the phone "
                                "at where it should be and ask me to check again.")  # fmt: skip
        d, score, home = min(sure, key=lambda s: s[0])
        hour, dist = clock_and_distance(cam_home, home)
        where = f"at {hour} o'clock, {_metres(dist)} away"
        position = [round(float(v), 3) for v in home]
        if d > NEARBY_M:
            return Verification("uncertain", f"I can see a {obj.label}, but not where yours was. It may be another "
                                "one.", round(d * 100), round(score, 2), position)  # fmt: skip
        if d <= SAME_PLACE_M:
            if score < SURE_SCORE and self.vision is not None and self.vision.is_visible(obj.label, jpeg) == "no":
                return Verification("uncertain", f"I'm not sure that's your {name}. Feel in front of you, {where}.",
                                    round(d * 100), round(score, 2), position)  # fmt: skip
            self._remember(obj, last, home, score, moved=False)
            return Verification(
                "confirmed", f"Found it. Your {name} {verb} {where}.", round(d * 100), round(score, 2), position
            )
        self._remember(obj, last, home, score, moved=True)
        return Verification("found_nearby", f"Your {name} {verb} here, but moved: {where}. I've updated my memory.",
                            round(d * 100), round(score, 2), position)  # fmt: skip

    def _remember(self, obj, last: Observation, home: np.ndarray, score: float, moved: bool) -> None:
        if moved:
            for o in obj.observations:
                o.stale = True  # the old place is history now
            obj.corrections.height_m = None
        obj.observations.append(
            Observation(self.new_id("ob"), obj.id, last.scan_id, self.clock.now(), Position(*map(float, home)), score)
        )
        self.objects.save(obj)
