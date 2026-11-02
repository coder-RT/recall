# Usability session with a blind or low-vision tester

One moderated session, about 60 minutes, in the room Recall has scanned. It answers the Impact question honestly:
does Recall help someone find their things faster and with less effort than searching by touch, and can they use
every part of it without looking?

The automated usability tests (`apps/ios/RecallUITests/UsabilityTests.swift`, `apps/web/e2e/usability.spec.ts`) check
that each task can be done with VoiceOver labels and the keyboard within a few actions. This session checks what no
test can: whether it works for a person.

## Before a blind or low-vision tester is available

The author runs the same five tasks with the screen off: VoiceOver on, then **Screen Curtain** (three-finger
triple-tap), so the screen stays black and only speech and touch are left. Same tasks, same timing, recorded with
`results-template.md` as participant **P0 (sighted, screen off)**.

This is a check that nothing depends on looking. It is **not** a substitute for a blind or low-vision tester, and it
is never reported as one.

## Files

| File | Use |
|---|---|
| `consent.md` | Read aloud before starting. Two separate yes/no answers. |
| `session-plan.md` | Setup, the five tasks, what to measure, what to say and not say. |
| `questionnaire.md` | Seven spoken questions at the end. |
| `results-template.md` | Copy it per session and fill it in. |

## Where results go

- The filled-in copy stays private: `docs/private/usability/<date>-P1.md` (gitignored). It may name the person.
- Only an anonymised summary (participant code, times, success, scores, issues) goes into `evals/results.md`.
- Quotes or video appear in the demo only with the second "yes" in the consent.

## What you need

- The iPhone with Recall, paired with the Mac running `make live`; a processed scan of the room.
- Three everyday objects (keys, glasses, a wallet) and their positions tape-measured beforehand.
- A stopwatch (or the phone's), this folder printed or on a laptop, and a second person nearby if you can.
- A clear walking path: nothing on the floor, doors fully open or closed, no sharp corners at head height.
