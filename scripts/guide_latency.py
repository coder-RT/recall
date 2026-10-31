"""Time the Guide on real questions against the running API: python scripts/guide_latency.py [label].

Uses RECALL_DEVICE_KEY and RECALL_HOME_ID from .env (never printed). Prints p50/p90 of the API's latency_ms and the
model calls behind each answer; with a label, appends the table to docs/verification.md.
"""

from __future__ import annotations

import statistics
import sys
from datetime import UTC, datetime
from pathlib import Path

import httpx

ROOT = Path(__file__).resolve().parents[1]
QUESTIONS = [
    "Where are my keys?", "Where did I leave my glasses?", "Where is my laptop?", "Where is my bag?",
    "Have you seen a bottle?", "Where's my book?", "Where are my keys", "Where is the laptop",
    "Where did I put my reading glasses?", "Where is my umbrella?",
]  # fmt: skip


def env() -> dict[str, str]:
    out = {}
    for line in (ROOT / ".env").read_text().splitlines():
        if "=" in line and not line.lstrip().startswith("#"):
            k, v = line.split("=", 1)
            out[k.strip()] = v.strip().strip('"').strip("'")
    return out


def main() -> int:
    e = env()
    api = e.get("RECALL_API_URL", "http://localhost:8000")
    headers = {"Authorization": f"Bearer {e['RECALL_DEVICE_KEY']}"}
    rows = []
    with httpx.Client(base_url=api, headers=headers, timeout=60) as c:
        for q in QUESTIONS:
            r = c.post("/ask", json={"home_id": e.get("RECALL_HOME_ID", "flat"), "question": q})
            r.raise_for_status()
            a = r.json()
            rows.append((q, a["latency_ms"], a["tool_calls"], a["text"]))
            print(f"{a['latency_ms']:>6} ms  {a['tool_calls']} tools  {q!r} -> {a['text'][:90]}")
    ms = sorted(x[1] for x in rows)
    p50, p90 = statistics.median(ms), ms[int(0.9 * (len(ms) - 1))]
    print(f"p50 {p50:.0f} ms, p90 {p90} ms over {len(ms)} questions")
    if len(sys.argv) > 1:
        stamp = datetime.now(UTC).strftime("%Y-%m-%d %H:%M UTC")
        lines = [f"\n### Guide latency, {sys.argv[1]} ({stamp}, `scripts/guide_latency.py`)\n",
                 f"p50 **{p50:.0f} ms**, p90 {p90} ms, {len(ms)} questions on the real memory.\n",
                 "| Question | ms | Tool calls | Answer |", "|---|---|---|---|"]  # fmt: skip
        lines += [f"| {q} | {m} | {t} | {a.replace('|', '/')} |" for q, m, t, a in rows]
        with (ROOT / "docs" / "verification.md").open("a") as f:
            f.write("\n".join(lines) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
