"""Every test suite in one run, kept as evidence: `make test-all [SUITES="api pipeline ..."] [ONLY="<UI tests>"]`.

Each suite's full output goes to data/test-runs/<UTC time>/<suite>.log (data/ is gitignored: logs never reach git),
with summary.json beside them; one line per run is appended to data/test-runs/runs.jsonl and history.md. The Mac is
kept awake (caffeinate) while it runs. Standard library only.
"""

from __future__ import annotations

import json
import os
import re
import signal
import subprocess
import sys
import time
from datetime import UTC, datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RUNS = ROOT / "data" / "test-runs"
SIM = os.environ.get("IOS_SIMULATOR", "6B268129-3A24-4646-BC3B-85D6D308C694")
IOS = ROOT / "apps" / "ios"
WATCH_SIM = os.environ.get("WATCH_SIMULATOR", "259C80D4-4128-41F3-8E00-3F6FAE56C600")  # Apple Watch Ultra 4
XCODE_FLAGS = ["-destination", f"id={SIM}", "-skipPackagePluginValidation", "-skipMacroValidation"]

# name -> (working directory, command, how to read the counts)
SUITES: dict[str, tuple[Path, list[str], str]] = {
    "api": (ROOT / "services/api", ["uv", "run", "pytest"], "pytest"),
    "pipeline": (ROOT / "services/pipeline", ["uv", "run", "pytest"], "pytest"),
    "lint": (ROOT, ["make", "lint"], "exit"),
    "imports": (ROOT, ["make", "lint-imports"], "imports"),
    "web-types": (ROOT / "apps/web", ["pnpm", "-s", "typecheck"], "exit"),
    "web-e2e": (ROOT / "apps/web", ["pnpm", "-s", "test:e2e", "--reporter=line"], "playwright"),
    "ios-unit": (IOS / "Packages/RecallKit", ["xcodebuild", "test", "-scheme", "RecallKit-Package", *XCODE_FLAGS],
                 "swift-testing"),
    "ios-ui": (IOS, ["xcodebuild", "test", "-project", "Recall.xcodeproj", "-scheme", "Recall", *XCODE_FLAGS], "xctest"),
    "watch-build": (IOS, ["xcodebuild", "build", "-project", "Recall.xcodeproj", "-scheme", "RecallWatch", "-destination",
                          f"platform=watchOS Simulator,id={WATCH_SIM}", "-skipPackagePluginValidation",
                          "-skipMacroValidation"], "build"),
}  # fmt: skip
XCODE_DONE = re.compile(r"\*\* (TEST SUCCEEDED|TEST FAILED|BUILD FAILED) \*\*")


def git(*args: str) -> str:
    return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True).stdout.strip()


def counts(kind: str, text: str, code: int) -> dict:
    """Passed / failed / skipped as the tool reports them; failing test names when it lists them."""
    out: dict = {}
    if kind == "pytest":
        for n, what in re.findall(r"(\d+) (passed|failed|skipped|errors?)", text.splitlines()[-1] if text else ""):
            out[what.rstrip("s") if what.startswith("error") else what] = int(n)
        out["failing"] = sorted(set(re.findall(r"^FAILED (\S+)", text, re.M)))
    elif kind == "playwright":
        for n, what in re.findall(r"^\s+(\d+) (passed|failed|flaky|skipped)", text, re.M):
            out[what] = int(n)
    elif kind == "swift-testing":
        out["passed"] = sum(int(n) for n in re.findall(r"Test run with (\d+) tests? in \d+ suites? passed", text))
        out["failed"] = len(set(re.findall(r"✘ Test (\S+)", text)))
    elif kind == "xctest":
        out["passed"] = len(set(re.findall(r"Test Case '-\[(\S+ \S+)\]' passed", text)))
        failing = sorted(set(re.findall(r"Test Case '-\[(\S+ \S+)\]' failed", text)))
        out["failed"], out["failing"] = len(failing), failing
        out["skipped"] = len(set(re.findall(r"Test Case '-\[(\S+ \S+)\]' skipped", text)))
    elif kind == "imports":
        m = re.findall(r"Contracts: (\d+) kept, (\d+) broken", text)
        out["kept"], out["broken"] = sum(int(k) for k, _ in m), sum(int(b) for _, b in m)
    return {k: v for k, v in out.items() if v or k in ("passed", "failed")}


def run(name: str, folder: Path) -> dict:
    cwd, cmd, kind = SUITES[name]
    if name == "ios-ui" and os.environ.get("ONLY"):  # e.g. ONLY="AccessibilityTests/testPrivacy UsabilityTests"
        cmd = cmd + [f"-only-testing:RecallUITests/{t}" for t in os.environ["ONLY"].split()]
    log = folder / f"{name}.log"
    started = time.monotonic()
    with log.open("w") as f:
        f.write(f"$ {' '.join(cmd)}  (in {cwd.relative_to(ROOT) or '.'})\n\n")
        f.flush()
        p = subprocess.Popen(cmd, cwd=cwd, stdout=f, stderr=subprocess.STDOUT, start_new_session=True)
        if kind in ("swift-testing", "xctest"):
            # xcodebuild prints its verdict and then can hang for minutes; stop it once the verdict is in
            while p.poll() is None and not XCODE_DONE.search(log.read_text(errors="replace")):
                time.sleep(5)
            time.sleep(3)
            if p.poll() is None:
                os.killpg(p.pid, signal.SIGTERM)
        p.wait()
    text = log.read_text(errors="replace")
    verdict = XCODE_DONE.search(text)
    code = (0 if verdict.group(1) == "TEST SUCCEEDED" else 1) if verdict else p.returncode
    c = counts(kind, text, code)
    if kind in ("swift-testing", "xctest") and not c.get("passed") and not c.get("failed"):
        first = re.search(r"^(/\S+\.swift:\d+:\d+: error: .+)$", text, re.M)  # it never ran: say why
        c["build_error"] = first.group(1).split("/apps/")[-1] if first else "the build failed (see the log)"
    ok = code == 0 and not c.get("failed") and not c.get("broken")
    return {"suite": name, "ok": ok, "exit": code, "seconds": round(time.monotonic() - started, 1), **c,
            "log": str(log.relative_to(ROOT))}  # fmt: skip


def main() -> int:
    chosen = (os.environ.get("SUITES") or " ".join(SUITES)).split()
    unknown = [s for s in chosen if s not in SUITES]
    if unknown:
        print(f"Unknown suite(s): {', '.join(unknown)}. Choose from: {', '.join(SUITES)}.")
        return 2
    stamp = datetime.now(UTC)
    folder = RUNS / stamp.strftime("%Y-%m-%dT%H%M%SZ")
    folder.mkdir(parents=True, exist_ok=True)
    if any(s.startswith("ios") for s in chosen):
        # a status bar override left by a screenshot run breaks the accessibility audits
        subprocess.run(["xcrun", "simctl", "status_bar", SIM, "clear"], capture_output=True)
    keep_awake = subprocess.Popen(["caffeinate", "-i", "-w", str(os.getpid())])
    results = []
    try:
        for name in chosen:
            print(f"▶ {name} …", flush=True)
            r = run(name, folder)
            results.append(r)
            print(f"  {'✓' if r['ok'] else '✗'} {name}: {line(r)}  ({r['seconds']} s)", flush=True)
    finally:
        keep_awake.terminate()
    summary = {
        "at": stamp.isoformat(),
        "commit": git("rev-parse", "--short", "HEAD"),
        "uncommitted_changes": bool(git("status", "--porcelain")),
        "ok": all(r["ok"] for r in results),
        "suites": results,
    }
    (folder / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    with (RUNS / "runs.jsonl").open("a") as f:
        f.write(json.dumps(summary) + "\n")
    history = RUNS / "history.md"
    if not history.exists():
        history.write_text("# Test runs\n\nOne line per `make test-all`; full logs in each run's folder.\n\n"
                           "| When (UTC) | Commit | Result | Suites |\n|---|---|---|---|\n")  # fmt: skip
    with history.open("a") as f:
        suites = "; ".join(f"{r['suite']} {line(r)}" for r in results)
        dirty = "+" if summary["uncommitted_changes"] else ""
        f.write(f"| {stamp:%Y-%m-%d %H:%M} | {summary['commit']}{dirty} | {'pass' if summary['ok'] else 'FAIL'} "
                f"| {suites} |\n")  # fmt: skip
    print(f"\n{'All passed' if summary['ok'] else 'Some failed'}. Logs: {folder.relative_to(ROOT)}/")
    return 0 if summary["ok"] else 1


def line(r: dict) -> str:
    parts = [f"{r[k]} {k}" for k in ("passed", "failed", "skipped", "flaky", "kept", "broken") if k in r]
    if r.get("build_error"):
        parts.append("did not build: " + r["build_error"])
    if r.get("failing"):
        parts.append("failing: " + ", ".join(r["failing"][:5]))
    return ", ".join(parts) or ("ok" if r["ok"] else f"exit {r['exit']}")


if __name__ == "__main__":
    sys.exit(main())
