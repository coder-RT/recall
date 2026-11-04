# Evaluation results

Dated measurements on real scans. Each row names what was run, so it can be run again.

## Recognising the room from a photo (2026-11-02)

The photo matcher behind `POST /homes/{home_id}/locate`: ORB features of one camera photo matched against a scan's
place index (every keyframe's ORB features lifted to 3D with the phone's own LiDAR depth and ARKit pose), then PnP
with RANSAC. Classic OpenCV, no model. Data: the author's living room, six scans made Oct 30 to Nov 2 with the
iPhone 16 Pro; the reference is the published scan (`bb449f4c`, 162 keyframes).

| Test | Photos | Fix (≥ 30 inliers, ≤ 4 px) | Right | Accuracy | Time on the Mac (M5 Pro) |
|---|---|---|---|---|---|
| Held-out keyframes of the same scan (index from the other half) | 81 | 100% | 100% | 1.2 cm median, 4.1 cm p90; 0.55° median | 22 ms median, 25 ms p90 |
| Photos from four other sessions (Nov 1 to Nov 2) | 242 | 62% | 90% | — | 33 to 35 ms median |
| Photos from the oldest session (Oct 30; furniture since moved) | 19 | 26% | 60% | — | 34 ms median |

"Right" for other sessions: their ARKit worlds differ from the reference, so a fix is right when the scan-to-scan
transform it implies agrees (within 25 cm and 10°) with the one most fixes agree on.

Threshold sweep over all 261 photos from other sessions (fix rate, then share right):

| Inliers ≥ | 15 | 20 | 30 | 40 | 50 | 70 | 100 |
|---|---|---|---|---|---|---|---|
| Fix rate | 66% | 63% | 59% | 53% | 49% | 38% | 30% |
| Right | 87% | 89% | 89% | 94% | 95% | 98% | 97% |

**What the phone does with it:** a photo pose is used only when two fixes in a row agree within 25 cm and 10°
(`FixAgreement`), and ARKit's own match replaces it as soon as it comes. With about 6 in 10 photos giving a fix and
one photo a second, two agreeing fixes typically take 2 to 4 s.

**Found on the way:** none of the five rescans of this room was recognised by ARKit at the start of the rescan (all
are marked `fresh` in the database), which is the problem this feature addresses.

To run it again: `make place-index`, then
`cd services/api && uv run python ../../evals/locate_photo.py bb449f4c 926c7d73 56c966eb 63bdddb5 236dc98e 7a736bf2`.

**Still to measure on the iPhone:** time from opening "See it in AR" to the labels, from five start spots (doorway,
corner, sofa, facing a wall, hallway), before and after; and whether a grown room map matches from a spot that failed
before.

## Real use, from the app's own logs (Oct 31 to Nov 4, 2026)

Counted from `data/recall.db` (`audit_events`, `answer_log`): one person, one flat, the author's iPhone. Real use, not a
study, and the walks were not all blindfolded.

| Measure | Result |
|---|---|
| Answers grounded | 49 of 49 |
| Arrival checks | 31: 22 confirmed, 4 found nearby, 5 not seen from the phone |
| Gap between camera and memory, confirmed arrivals | 2 cm median (n = 22) |
| Guide, question to answer | 2.3 s median (n = 46) |
| Speech to text, Muse Voice Transcribe | 2.3 s median (n = 61) |
| Reply after a find, live test of 20 phrasings | 19 as expected, 950 ms median |

The 4 "found nearby" include the 82 cm false move of 2 Nov that the arrival-check rule of Nov 4 now guards against.
