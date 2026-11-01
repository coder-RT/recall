# Installing Recall

Step by step, for a person or for an AI coding agent. Every step has the command, what you should see, and what to
do if you don't. Do the steps in order; stop at the first one whose check fails.

**Pick a path.** Each builds on the one before.

| Path | You get | Needs | Time |
|---|---|---|---|
| **A. Website** | The landing page and the real 3D scan at `/homes/flat/viewer` | Any Mac, Linux or Windows (WSL) with Node 22 | 5 min |
| **B. Demo, no keys** | The API answering "where are my keys?" from a recorded real scan, with recorded Muse Spark Open replies | A Mac with Apple silicon, or Linux | 10 min |
| **C. Live** | Real Meta model calls, the scan pipeline, and the iPhone app scanning your own room | A Mac with Apple silicon (24 GB+), keys, an iPhone with LiDAR (iOS 26) | 45 min |

Nothing asks for an account on Recall. Path C needs your own Meta Model API key (and a Baseten key for Muse Spark
Open); A and B need no keys.

---

## For AI agents

If you are an agent installing this for someone:

1. Run each command exactly as written, from the folder the step names. Don't skip a check.
2. **Never print, log or commit a key.** Keys go only into `.env` at the repo root, which git ignores. Ask the person
   to paste keys into `.env` themselves; don't ask them to send keys to you.
3. If a check fails, try the "If it fails" line once, then stop and report the step number, the command and its
   last 20 lines of output.
4. Don't change any file in the repo to make a step pass.

---

## 0. Get the code (all paths)

```bash
git clone https://github.com/coder-RT/recall.git
cd recall
```

**Check:** `ls` shows `apps`, `services`, `Makefile`, `README.md`, `INSTALL.md`.

---

## Path A: the website

### A1. Node 22 and pnpm

```bash
node --version        # must print v22 or newer
corepack enable       # provides the pnpm version pinned in package.json
pnpm --version
```

**Check:** `node` prints `v22.x` or newer; `pnpm` prints a version.
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
- `http://localhost:3000/homes/flat/viewer`: the **real scan** of the author's living room. It's geometry only: no
  photo of the room is published. You'll see:
  - the 3D room;
  - which Meta model made each part;
  - the measured numbers;
  - what SAM 3.1 found;
  - the drawings;
  - what a robot gets.

**Check:** the viewer page shows the badge "Real scan · not a simulation" and a 3D room you can drag to turn.

Path A is done. Stop the server with `Ctrl+C`.

---

## Path B: the demo API, no keys

### B1. uv (Python manager)

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
uv --version
```

**Check:** prints a version. uv downloads Python 3.12 by itself in the next step; you don't need to install Python.

### B2. Install the services

From the repo root:

```bash
make setup
```

This runs `uv sync` for both Python services, `pnpm install`, generates the API models from the spec, and creates
the local database.

**Check:** the last lines show no `Error`, and `ls data/` shows `recall.db`.
**If it fails:** run `make setup` once more (a network hiccup during the first download is the usual cause).

### B3. Run the demo

```bash
make demo
```

**Check:** it prints a list of questions to try, and `Uvicorn running on http://127.0.0.1:8000`.

### B4. Ask it something

In a second terminal:

```bash
curl -s -X POST http://127.0.0.1:8000/ask \
  -H "Authorization: Bearer demo" -H "Content-Type: application/json" \
  -d '{"home_id": "flat", "question": "Where are my keys?"}'
```

**Check:** a JSON answer naming a place in the room, with `"model": "replay:muse-spark-open (recorded)"`. Every demo
answer is labelled as recorded.

API documentation (Swagger UI) is at `http://127.0.0.1:8000/docs`.

### B5. The tests (optional)

```bash
make test lint lint-imports
```

**Check:** every suite ends with `passed` and `Contracts: 2 kept, 0 broken`.

---

## Path C: live, with your own room

### C1. Keys

Create `.env` in the repo root (git ignores it). Put each value in yourself:

```bash
META_MUSE_API_KEY=        # Meta Model API key from https://dev.meta.ai (SAM 3.1, Muse Voice Transcribe, Muse Spark)
BASETEN_API_KEY=          # Baseten key, for Muse Spark Open (the Guide); optional with LLM_PROVIDER=meta
RECALL_DEVICE_KEY=        # any long random string; the phone pairs with it. e.g. the output of: openssl rand -hex 16
```

Only Baseten key missing? Add `LLM_PROVIDER=meta` to `.env`. The Guide then runs on the hosted Muse Spark on the Meta
Model API.

**Check:** `grep -c "=" .env` prints at least `3`. Don't print the file.

### C2. Start the API and the scan worker

```bash
make live
```

**Check:** `Uvicorn running on http://0.0.0.0:8000`, and the worker prints `pipeline server on 127.0.0.1:8766`. The
first scan downloads MapAnything's weights (`facebook/map-anything-apache`, a few GB) once.

### C3. Check every model and service once (optional)

```bash
make probes
```

**Check:** one line per model or service, saying whether it worked (the results are also added to
`docs/verification.md`). This step makes small paid calls with your keys.

### C4. The iPhone app

Needs Xcode (current version), an iPhone with LiDAR (12 Pro or newer) on iOS 26, and a free Apple ID.

```bash
brew install xcodegen
cd apps/ios
xcodegen generate
open Recall.xcodeproj
```

In Xcode:
1. Select the **Recall** target → Signing & Capabilities → Team: your Apple ID.
2. Plug in the iPhone, select it as the run destination, and press Run.

**Check:** the app opens on the **Find** tab.
**If it fails:** on the phone, open Settings → General → VPN & Device Management and trust your developer
certificate, then press Run again.

### C5. Pair the phone with the Mac

The phone must reach the Mac. On the same Wi-Fi, use the Mac's address (System Settings → Wi-Fi → Details → IP
address):

```bash
make pair URL=http://<mac-ip>:8000 HOME_ID=flat
```

Scan the QR code it shows with the iPhone's Camera app.

**Check:** in the app's Settings, **Test connection** says it reached the Mac.

### C6. Scan a room and see it

1. In the app: **Scans** → **Start a scan**, name the room, and walk it slowly as the voice says. Then tap **Upload to
   the Mac**.
2. Wait until the app says the room is ready (about 2 minutes). **Find** now shows the room's map.
3. Ask "where are my keys?" by voice or by typing, then **Take me there**.
4. To see your own scan in the website's viewer:

   ```bash
   make viewer HOME_ID=flat
   cd apps/web && pnpm dev
   ```

   Open `http://localhost:3000/homes/<your-home>/viewer`. Your export stays on your computer: git ignores it.

---

## Every test, with logs kept

```bash
caffeinate -i make test-all        # macOS; on Linux: make test-all
```

This runs every suite, in this order:
- API, pipeline;
- lint, the architecture rules;
- web types, web browser tests;
- iPhone unit and UI tests (on a Mac).

Each run's logs go to `data/test-runs/<time>/` (git ignores it). To run some suites only, name them:
`make test-all SUITES="api pipeline"`.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `make: uv: No such file or directory` | Open a new terminal after B1, or run `source ~/.local/bin/env` |
| `pnpm: command not found` | `corepack enable` (A1) |
| Port 8000 in use | `lsof -i :8000` to find it, or `make demo PORT=8001` |
| The phone can't reach the Mac | Same Wi-Fi, the Mac's firewall allows incoming connections for Python, and the URL uses the Mac's IP, not `localhost` |
| The first scan is slow | MapAnything's weights download once (C2); later scans take about 2 minutes |
| `make demo` says the sample is missing | Pull the latest `main`: `git pull` |
