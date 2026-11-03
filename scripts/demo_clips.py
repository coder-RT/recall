"""`make demo-clips`: cut the real iPhone screen recordings into short clips for the demo page, on this computer only.

Reads docs/private/demo-clips/segments.json (which recording, which seconds, the captions) and the recordings in
docs/private/video_recording/, both private. Writes apps/web/public/local-video/<id>.mp4 and clips.json, which git
ignores: the clips show the home through the camera, so they never reach git or the hosted site unless the owner
decides to publish them (docs/private/demo-clips/PUBLISH.md). Needs ffmpeg. Standard library only.
"""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PRIVATE = ROOT / "docs" / "private"
SEGMENTS = PRIVATE / "demo-clips" / "segments.json"
RECORDINGS = PRIVATE / "video_recording"
OUT = ROOT / "apps" / "web" / "public" / "local-video"
WIDTH = 590  # half the iPhone 16 Pro screen width: sharp in a phone frame, a few MB per minute


def cut(src: Path, start: float, end: float, dst: Path) -> None:
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-ss", str(start), "-to", str(end), "-i", str(src),
         "-vf", f"scale={WIDTH}:-2,fps=30", "-c:v", "libx264", "-preset", "medium", "-crf", "28", "-pix_fmt", "yuv420p",
         "-c:a", "aac", "-b:a", "96k", "-movflags", "+faststart", str(dst)],
        check=True,
    )  # fmt: skip


def main() -> int:
    if not SEGMENTS.exists():
        print(f"No {SEGMENTS.relative_to(ROOT)}: nothing to cut. The demo page shows its simulated phone screen.")
        return 0
    if not shutil.which("ffmpeg"):
        print("ffmpeg is needed: brew install ffmpeg")
        return 1
    OUT.mkdir(parents=True, exist_ok=True)
    clips = []
    for clip in json.loads(SEGMENTS.read_text())["clips"]:
        src = RECORDINGS / clip["source"]
        if not src.exists():
            print(f"  skipped {clip['id']}: {src.name} is not in {RECORDINGS.relative_to(ROOT)}")
            continue
        dst = OUT / f"{clip['id']}.mp4"
        cut(src, clip["start"], clip["end"], dst)
        # the page gets what it shows, never where the recording came from
        clips.append({k: clip[k] for k in ("id", "kind", "thing", "title", "recorded", "walk", "captions") if k in clip}
                     | {"file": dst.name, "seconds": clip["end"] - clip["start"]})  # fmt: skip
        print(f"  {dst.relative_to(ROOT)}  {clip['end'] - clip['start']} s  {dst.stat().st_size / 1e6:.1f} MB")
    manifest = json.dumps({"source": "local", "clips": clips}, indent=1, ensure_ascii=False)
    (OUT / "clips.json").write_text(manifest + "\n")
    print(f"Wrote {len(clips)} clips to {OUT.relative_to(ROOT)} (gitignored: this computer only).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
