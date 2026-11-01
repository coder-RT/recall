# RECALL

**Recall remembers where you put things, and walks you back to them.**

Recall is a voice-first 3D memory of your home for blind and low-vision people. You walk through each room once
with an iPhone, guided step by step by voice. Recall builds a 3D map in metres and remembers the furniture and the
everyday things it saw. From then on, you ask and it answers out loud, then guides you there.

Every model Recall calls is a Meta model:
- MapAnything builds the 3D map;
- SAM 3.1 finds the things;
- Muse Voice Transcribe hears you;
- Muse Spark Open understands the question and words the answer.

Places, distances and times always come from the 3D map, never from a guess.

**What it answers**

- **"Where are my keys?"**: "On the hallway shelf, second level, chest height. Seen 12 minutes ago."
- **"Have you seen my reading glasses?"**: the landmark first, then the shelf and height, then when it was seen.
- **"Where's my grey bag?"**: colours are measured from the scan's photos.
- **"Why do you think so?"**: what the camera saw, and when.
- **"Take me there"**: spoken clock-face steps as you walk, then the camera checks the thing is really there when you
  arrive.
- **Scan a room**: a voice-led walkthrough that says where to hold the phone, shows what the LiDAR has covered, and
  grades the scan with tips.
- **Apple Watch (preview)**: pick a thing with the Digital Crown and follow taps on your wrist.
- **Robots and other apps (off by default)**: read-only access to the map and the things, never photos.

Built during the Meta Global AI Developer Hackathon, Oct 26 to Nov 4, 2026.
[Source on GitHub](https://github.com/coder-RT/recall) · [How Meta Muse is used](https://github.com/coder-RT/recall/blob/main/docs/muse.md) ·
[Privacy](https://github.com/coder-RT/recall/blob/main/docs/privacy.md)

---

# Installing Recall

Step by step, for a person or for an AI coding agent. Every step has the command, what you should see, and what to
do if you don't. Do the steps in order, and stop at the first check that fails.

**Pick a path.** Each one builds on the one before.

| Path | You get | Needs | Time |
|---|---|---|---|
| **A. Website** | The landing page and the real 3D scan at `/homes/flat/viewer` | macOS, Linux or Windows (WSL) with Node 22 | 5 min |
| **B. Demo, no keys** | The API answering "where are my keys?" from a recorded real scan, with recorded Muse Spark Open replies | macOS (Apple silicon) or Linux | 10 min |
| **C. Live** | Real Meta model calls, the scan pipeline, and the iPhone app scanning your own room | A Mac with Apple silicon (24 GB memory or more), your own keys, an iPhone with LiDAR on iOS 26 | 45 min |

Nothing asks for a Recall account. Paths A and B need no keys. Path C needs your own Meta Model API key, and a
Baseten key for Muse Spark Open.

> **This guide never contains a key.** Keys go only in a file called `.env` at the repo root, which git ignores.

---

## For AI agents

If you are an agent installing Recall for someone:

1. Run each command exactly as written, from the folder the step names. Don't skip a check.
2. **Never print, log or commit a key.** Ask the person to paste their keys into `.env` themselves. Don't ask them to
   send keys to you.
3. If a check fails, try its "If it fails" line once. Then stop and report the step number, the command and the last
   20 lines of its output.
4. Don't change any file in the repo to make a step pass.

---

## 0. Get the code (all paths)

```bash
git clone https://github.com/coder-RT/recall.git
cd recall
```

**Check:** `ls` shows `apps`, `services`, `docs`, `Makefile` and `README.md`.

---

## Path A: the website

### A1. Node 22 and pnpm

```bash
node --version        # must print v22 or newer
corepack enable       # provides the pnpm version pinned in package.json
pnpm --version
```

**Check:** `node` prints `v22.x` or newer, and `pnpm` prints a version.
**If it fails:** install Node 22 from https://nodejs.org (or `brew install node@22` on a Mac), then run the commands
again.

### A2. Install and start

```bash
pnpm install
cd apps/web
pnpm dev
```

**Check:** the terminal prints `Local: http://localhost:3000`.
**If it fails:** if port 3000 is busy, run `pnpm dev --port 3001` and use 3001 below.

### A3. Open it

- `http://localhost:3000/`: the landing page.
- `http://localhost:3000/homes/flat/viewer`: the **real scan** of the author's living room. It is geometry only, and
  no photo of the room is published. It shows:
  - the 3D room;
  - which Meta model made each part;
  - the measured numbers;
  - what SAM 3.1 found;
  - the floor-plan drawings;
  - what a robot gets.

**Check:** the viewer shows the badge "Real scan · not a simulation" and a 3D room you can drag to turn.

Path A is done. Stop the server with `Ctrl+C`.

---

## Path B: the demo API, no keys

### B1. uv, the Python manager

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
uv --version
```

**Check:** it prints a version. uv downloads Python 3.12 itself in the next step, so you don't need to install
Python.
**If it fails:** open a new terminal so `uv` is on your PATH, then run `uv --version` again.

### B2. Install the services

From the repo root:

```bash
make setup
```

This step:
- installs both Python services (`uv sync`) and the web app (`pnpm install`);
- generates the API models from the OpenAPI spec;
- creates the local database.

**Check:** no line says `Error`, and `ls data/` shows `recall.db`.
**If it fails:** run `make setup` once more. A network hiccup during the first download is the usual cause.

### B3. Run the demo

```bash
make demo
```

**Check:** it prints "Recall demo: Recorded output of a real run…", a list of questions to try, and
`Uvicorn running on http://127.0.0.1:8000`.

### B4. Ask it something

In a second terminal:

```bash
curl -s -X POST http://127.0.0.1:8000/ask \
  -H "Authorization: Bearer demo" -H "Content-Type: application/json" \
  -d '{"home_id": "flat", "question": "Where are my keys?"}'
```

**Check:** a JSON answer like `"Your keys are in the Living room near the desk at waist height, seen yesterday at
04:21."`, with `"model": "replay:muse-spark-open (recorded)"`. Every demo answer is labelled as recorded.

The API documentation (Swagger UI) is at `http://127.0.0.1:8000/docs`.

### B5. Run the tests (optional)

```bash
make test lint lint-imports
```

**Check:** both test runs end in `passed` with no failures, ruff says `All checks passed!`, and import-linter says
`Contracts: 2 kept, 0 broken` for each service.

---

## Path C: live, with your own room

### C1. Keys

Create `.env` in the repo root (git ignores it) and type each value in yourself:

```bash
META_MUSE_API_KEY=        # your Meta Model API key (SAM 3.1, Muse Voice Transcribe, Muse Spark)
BASETEN_API_KEY=          # your Baseten key, for Muse Spark Open (the Guide)
RECALL_DEVICE_KEY=        # any long random string you make up; the phone pairs with it
```

To make a device key: `openssl rand -hex 24`.
**No Baseten key?** Add `LLM_PROVIDER=meta`. The Guide then runs on hosted Muse Spark on the Meta Model API.

**Check:** `grep -c "=" .env` prints at least `3`. Don't print the file itself.

### C2. Start the API and the scan worker

```bash
make live
```

**Check:**
- `Uvicorn running on http://0.0.0.0:8000`;
- the worker prints `pipeline server on 127.0.0.1:8766`.

The first scan downloads MapAnything's weights (`facebook/map-anything-apache`, a few GB) once.

`make live` listens on your network so the phone can reach the Mac. Every route that touches your home needs the
device key, and the calls that reach a model are rate-limited. To keep the API on the Mac alone (for example behind a
tunnel), run `make live BIND=127.0.0.1`.

### C3. Check every model and service once (optional)

```bash
make probes
```

**Check:** one line per model or service, saying whether it worked. This step makes small paid calls with your keys.

### C4. The iPhone app

Needs Xcode (current version), an iPhone with LiDAR (iPhone 12 Pro or newer) on iOS 26, and a free Apple ID.

```bash
brew install xcodegen
cd apps/ios
xcodegen generate
open Recall.xcodeproj
```

In Xcode:
1. Select the **Recall** target → Signing & Capabilities → Team: your Apple ID.
2. Plug in the iPhone, select it as the run destination, and press **Run**.
3. On the first build, Xcode asks to trust the **OpenAPIGenerator** plugin (it generates the app's API client from
   the spec). Choose **Trust & Enable**.

**Check:** the app opens on the **Find** tab.
**If it fails:** on the phone, open Settings → General → VPN & Device Management, trust your developer certificate,
then press Run again.

### C5. Pair the phone with the Mac

The phone must reach the Mac. Use one of these addresses:

| How the phone reaches the Mac | Address to use |
|---|---|
| The same Wi-Fi | `http://<your Mac's IP address>:8000` (System Settings → Wi-Fi → Details) |
| Tailscale, from anywhere (both devices signed in to the same tailnet) | `http://<your Mac's Tailscale name>.ts.net:8000` (Tailscale encrypts the traffic) |

```bash
make pair URL=http://<address from the table>:8000 HOME_ID=flat
```

Scan the QR code with the iPhone's Camera app and tap the Recall banner. Recall asks **"Pair with this Mac?"** and
shows the address and the key's length, never the key itself. Tap **Pair** only if it is your Mac.

**Check:** in the app, **Settings → Test connection** says it reached the Mac.

You can also type the address and paste the key in Settings yourself. The key is in `.env` on the Mac.

### C6. Scan a room and see it

1. In the app, open **Scans** → **Start a scan**, name the room, and walk it slowly as the voice says. Then tap
   **Upload to the Mac**.
2. Wait until the app says the room is ready (about 2 minutes). **Find** now shows the room's map.
3. Ask "where are my keys?" by voice or by typing, then tap **Take me there**.
4. To see your own scan in the website's viewer:

   ```bash
   make viewer HOME_ID=flat
   cd apps/web && pnpm dev
   ```

   Open `http://localhost:3000/homes/flat/viewer`. Your export stays on your computer, and git ignores it.

### C7. The Apple Watch (preview)

Needs an Apple Watch paired with the iPhone. It was built for the Ultra 4, on watchOS 26 or newer.

1. **Install.** The Watch app is part of the iPhone app, so after C4 it installs on the paired Watch by itself. If it
   doesn't, open the iPhone's **Watch** app → Recall → **Install**.
2. **Scan with Location allowed.** Allow Location for Recall on the iPhone before you scan: the Watch walks by
   compass, and north comes from that scan. **Start the scan at the room's door**, because the Watch's walk starts
   where the scan began.
3. **Keep Recall on screen.** On the Watch, set Settings → General → Return to Clock → Recall → **After 1 hour**, so
   Recall stays up while you walk.
4. **Pick a thing.** Stand at the door with the iPhone in a pocket and open Recall on the Watch.
   - It says "Hi, I'm Recall. What should I find?" Say "keys", or turn the Digital Crown to pick a thing (it says
     each name).
   - Then press **Find it**, or double tap (pinch twice).
5. **Walk there.** Press **Walk there** (or double tap) and follow your wrist:

   | Tap on the wrist | Meaning |
   |---|---|
   | left-turn pattern | turn left |
   | right-turn pattern | turn right |
   | a single upward tap | facing the right way |
   | a click | each metre walked |
   | a long buzz | arrived |

   A double tap repeats the current step aloud.

**Check:** the Watch says where the thing is, and "You're there" at the end.
**If it fails:**
- "This room was scanned without a reliable compass": rescan with Location allowed.
- "Your iPhone didn't answer": keep it nearby, open Recall on it once, and ask again.

---

## Every test, with the logs kept

```bash
caffeinate -i make test-all        # macOS; on Linux: make test-all
```

This runs every suite:
- API and pipeline;
- lint and the architecture rules;
- web types and browser tests;
- iPhone unit and UI tests, and the Watch build (on a Mac with Xcode).

Each run's logs go to `data/test-runs/<time>/`, which git ignores. To run only some suites, name them:
`make test-all SUITES="api pipeline"`.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `make: uv: No such file or directory` | Open a new terminal after B1 |
| `pnpm: command not found` | `corepack enable` (A1) |
| Port 8000 in use | `lsof -i :8000` to find what's using it, or `make demo PORT=8001` |
| The phone can't reach the Mac | Same Wi-Fi (or both on Tailscale), the Mac's firewall allows incoming connections for Python, and the address uses the Mac's IP or Tailscale name, not `localhost` |
| Xcode: "Validate plug-in OpenAPIGenerator" | Choose Trust & Enable (C4). From the command line, add `-skipPackagePluginValidation` |
| The first scan is slow | MapAnything's weights download once (C2); later scans take about 2 minutes |
| "Too many requests" from the Mac | The calls that reach a model are rate-limited per key; wait a minute |
