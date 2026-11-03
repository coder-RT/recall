"""`make demo`: Recall's no-keys demo, told step by step.

It starts Recall's API on a memory built from a recorded real scan (samples/replay/flat) and the website beside it,
says what each step is doing, waits until both really answer, then prints the one page to open. The two servers'
own output goes to data/demo/api.log and data/demo/web.log (data/ is gitignored), so the terminal stays readable.
Ctrl+C stops both. Standard library only.

    python3 scripts/demo.py [--port 8000] [--web-port 3000]
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import signal
import socket
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
API = ROOT / "services" / "api"
WEB = ROOT / "apps" / "web"
SAMPLE = ROOT / "samples" / "replay" / "flat"
LOGS = ROOT / "data" / "demo"
ONLINE = "https://recall-ten-khaki.vercel.app/demo"
TTY = sys.stdout.isatty()


def style(code: str, text: str) -> str:
    return f"\033[{code}m{text}\033[0m" if TTY else text


def bold(text: str) -> str:
    return style("1", text)


def ok(text: str) -> str:
    return style("32", text)


def bad(text: str) -> str:
    return style("31", text)


def say(text: str = "", end: str = "\n") -> None:
    print(text, end=end, flush=True)


def step(n: int, title: str) -> None:
    say(f"{bold(f'[{n}/4]')} {title:<30}", end="")


def busy(port: int) -> bool:
    with socket.socket() as s:
        s.settimeout(0.3)
        return s.connect_ex(("127.0.0.1", port)) == 0


def answers(url: str) -> bool:
    try:
        with urllib.request.urlopen(url, timeout=5) as r:
            return r.status < 500
    except urllib.error.HTTPError as e:
        return e.code < 500
    except (urllib.error.URLError, OSError):
        return False


def wait_for(url: str, proc: subprocess.Popen, timeout: float) -> bool:
    """True once `url` answers; False if the process exits first or `timeout` passes."""
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        if proc.poll() is not None:
            return False
        if answers(url):
            return True
        time.sleep(0.4)
    return False


def start(cmd: list[str], cwd: Path, log: Path, env: dict[str, str]) -> subprocess.Popen:
    out = log.open("w")
    # its own process group, so Ctrl+C reaches only this script, which then stops the servers cleanly
    return subprocess.Popen(cmd, cwd=cwd, stdout=out, stderr=subprocess.STDOUT, env=env, start_new_session=True)


def stop(proc: subprocess.Popen | None) -> None:
    if proc is None or proc.poll() is not None:
        return
    for sig, wait in ((signal.SIGTERM, 5), (signal.SIGKILL, 2)):
        try:
            os.killpg(proc.pid, sig)
        except ProcessLookupError:
            return
        try:
            proc.wait(wait)
            return
        except subprocess.TimeoutExpired:
            continue


def tail(log: Path, n: int = 15) -> str:
    try:
        lines = log.read_text(errors="replace").splitlines()
    except OSError:
        return ""
    return "\n".join("    " + line for line in lines[-n:])


def failed(what: str, log: Path, mark: bool = True) -> None:
    if mark:
        say(bad("✗"))
    say(f"\n{bad(what)} The last lines of {log.relative_to(ROOT)}:\n{tail(log)}")


REPLAYED = re.compile(r"demo: replayed '(.+)'")


def follow(log: Path, done: threading.Event) -> None:
    """One line in the terminal per question the API answers (only the recorded questions are ever named)."""
    with log.open(errors="replace") as f:
        f.seek(0, os.SEEK_END)
        while not done.is_set():
            line = f.readline()
            if not line:
                time.sleep(0.3)
                continue
            if m := REPLAYED.search(line):
                say(f"  → asked “{m.group(1)}” · answered from the recording")
            elif "demo: a question that isn't recorded" in line:
                say("  → a question that isn't recorded: the API's reply lists the ones that are")


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--port", type=int, default=8000, help="the API's port (default 8000)")
    p.add_argument("--web-port", type=int, default=3000, help="the website's port (default 3000)")
    a = p.parse_args()

    meta = json.loads((SAMPLE / "meta.json").read_text())
    say(bold("Recall demo") + " · no keys, no account, nothing calls a model")
    say(meta["label"] + "\n")

    # 1. tools and ports, with the fix for each
    step(1, "Checking the tools")
    if not shutil.which("uv"):
        say(bad("✗"))
        say("\nuv (the Python manager) is needed:  curl -LsSf https://astral.sh/uv/install.sh | sh  then: make setup")
        return 1
    web = bool(shutil.which("pnpm")) and (WEB / "node_modules").is_dir()
    say(f"uv {ok('✓')}  website {ok('✓') if web else bad('✗') + ' (make setup installs it)'}")
    if busy(a.port):
        say(f"\n{bad(f'Port {a.port} is in use.')} See what is using it: lsof -i :{a.port}   or pick another: "
            f"make demo PORT={a.port + 1}")  # fmt: skip
        return 1
    if web and busy(a.web_port):
        say(f"\n{bad(f'Port {a.web_port} is in use.')} Another copy of the website may be running: open "
            f"http://localhost:{a.web_port}/demo, or stop it (lsof -i :{a.web_port}).")  # fmt: skip
        return 1

    # 2. what the demo is made of
    step(2, "Reading the recorded scan")
    result = json.loads((SAMPLE / "scan-result.json").read_text())
    say(f"{meta['room']}: {len(result['objects'])} things, {len(result['landmarks'])} pieces of furniture, "
        f"{len(meta['answers'])} recorded questions")  # fmt: skip

    LOGS.mkdir(parents=True, exist_ok=True)
    api_log, web_log = LOGS / "api.log", LOGS / "web.log"
    env = {k: v for k, v in os.environ.items() if k != "PORT"}  # make passes PORT on; it is the API's, not Next's
    api = site = None
    stop_following = threading.Event()

    def quit_now(*_: object) -> None:
        raise KeyboardInterrupt  # a closed terminal or a kill stops the servers the same way Ctrl+C does

    for sig in (signal.SIGTERM, signal.SIGHUP):
        signal.signal(sig, quit_now)
    try:
        # 3. the API: the memory is built through the real ingest code when it starts
        step(3, "Starting Recall's API")
        say("building the memory … ", end="")
        t0 = time.monotonic()
        api = start(["uv", "run", "python", "-m", "recall_api.infra.demo", "serve", "--port", str(a.port)],
                    API, api_log, env)  # fmt: skip
        if not wait_for(f"http://127.0.0.1:{a.port}/health", api, 120):
            failed("The API didn't start.", api_log)
            return 1
        say(f"{ok('ready')} on http://127.0.0.1:{a.port} ({time.monotonic() - t0:.1f} s)")

        # 4. the website; asking for /demo once also prepares the page, so the first visit is quick
        step(4, "Starting the website")
        if web:
            say("preparing the demo page (the first time takes up to 30 s) … ", end="")
            t0 = time.monotonic()
            site = start(["pnpm", "dev"], WEB, web_log, {**env, "PORT": str(a.web_port)})
            if not wait_for(f"http://localhost:{a.web_port}/demo", site, 180):
                failed("The website didn't start.", web_log)
                return 1
            say(f"{ok('ready')} ({time.monotonic() - t0:.1f} s)")
        else:
            say(f"skipped: no web app here. The same page is online: {ONLINE}")

        body = json.dumps({"home_id": "flat", "question": "Where are my keys?"})
        curl = (f"curl -s -X POST localhost:{a.port}/ask -H 'Authorization: Bearer demo' "
                f"-H 'Content-Type: application/json' -d '{body}'")  # fmt: skip
        page = f"http://localhost:{a.web_port}/demo" if web else ONLINE
        say(f"\n{bold(ok('Ready.'))} Open  {bold(page)}   ← ask, then walk")
        say(f"  The API:          http://127.0.0.1:{a.port}/docs   (device key: demo)")
        say(f"  From a terminal:  {curl}")
        say("  Every answer is Muse Spark Open's real reply, recorded once and replayed by Recall's own code;")
        say("  the routes come from the planner the phone uses, on the scan's floor.")
        logs = f"{api_log.relative_to(ROOT)}" + (f", {web_log.relative_to(ROOT)}" if web else "")
        say(f"  Logs: {logs}      Stop: Ctrl+C\n")

        threading.Thread(target=follow, args=(api_log, stop_following), daemon=True).start()
        while True:
            for proc, name, log in ((api, "The API", api_log), (site, "The website", web_log)):
                if proc is not None and proc.poll() is not None:
                    failed(f"{name} stopped unexpectedly.", log, mark=False)
                    return 1
            time.sleep(0.5)
    except KeyboardInterrupt:
        say("\nStopping …")
        return 0
    finally:
        stop_following.set()
        stop(site)
        stop(api)
        if api is not None:
            say("Stopped. The demo memory was temporary; nothing was saved.")


if __name__ == "__main__":
    sys.exit(main())
