"""What is kept on this Mac and what leaves it, under the current settings, in words for the person.

Only facts the configuration decides; the phone's and the website's privacy notes show this list as "right now".
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class Flow:
    what: str
    to: str
    when: str
    on_this_mac: bool = False


@dataclass(frozen=True)
class PrivacyFacts:
    stored_on: str
    sent: list[Flow]
    robot_access: bool
    audit_days: int


GUIDE = {
    "baseten_spark_open": ("Baseten: Muse Spark Open", False),
    "glimmer_hosted": ("Your Muse Glimmer host (Modal or Fireworks)", False),
    "lmstudio": ("Nobody: Muse Glimmer runs on this Mac (LM Studio)", True),
    "meta": ("Meta Model API: Muse Spark", False),
    "replay": ("Nobody: the recorded demo replays saved replies", True),
}
SCREEN = {
    "baseten_spark_open": ("Baseten: Muse Spark Open", False),
    "lmstudio": ("Nobody: Muse Glimmer runs on this Mac (LM Studio)", True),
}


def describe_privacy(
    guide_provider: str, screen_provider: str, storage: str, robot_access: bool, audit_days: int
) -> PrivacyFacts:
    guide_to, guide_local = GUIDE[guide_provider]
    sent = [
        Flow("Scan photos, about 50 per room (no depth, no sound)", "Meta Model API: SAM 3.1",
             "While this Mac processes a scan, to find furniture and things"),
        Flow("Your spoken question (a few seconds of audio)", "Meta Model API: Muse Voice Transcribe",
             "When you ask by voice"),
        Flow("Your question as text, and what memory says about the thing (names, rooms, heights, times; no photos)",
             guide_to, "Each time you ask", guide_local),
        Flow("One photo from the camera", "Meta Model API: SAM 3.1, and Muse Spark 1.1 only when SAM is unsure",
             "When you check on arrival"),
    ]  # fmt: skip
    if robot_access:
        screen_to, screen_local = SCREEN[screen_provider]
        sent += [
            Flow("The room map, things and furniture (no photos, your names or notes, or anyone's position)",
                 "Robots and agents you gave the robot key", "When a robot asks"),
            Flow("The object name a robot asked about", screen_to, "Before any robot request is answered",
                 screen_local),
        ]  # fmt: skip
    stored = "Your Cloudflare R2 bucket and this Mac" if storage == "r2" else "This Mac"
    return PrivacyFacts(stored, sent, robot_access, audit_days)
