"""make probes: one minimal REAL call per Meta model or service, timed, appended to docs/verification.md.

Never run in CI. Keys are read from .env and never printed, logged or written anywhere.
Each probe reports exactly what it sent (minus keys) and what came back, so adapters follow evidence.
"""

from __future__ import annotations

import base64
import json
import os
import subprocess
import sys
import tempfile
import time
from datetime import UTC, datetime
from pathlib import Path

import httpx

ROOT = Path(__file__).resolve().parents[2]
VERIFICATION = ROOT / "docs" / "verification.md"
TOOLS = json.loads((ROOT / "services/api/resources/tools.json").read_text())
META = "https://api.meta.ai/v1"
BASETEN = "https://inference.baseten.co/v1"
DOCS = {
    "meta": "https://dev.meta.ai/docs/api-reference/chat-completions/create-chat-completion",
    "models": "https://dev.meta.ai/docs/models",
    "vision": "https://dev.meta.ai/docs/image-understanding",
    "sam": "https://dev.meta.ai/docs/sam/segmenting",
    "asr": "https://dev.meta.ai/docs/api-reference/voice/transcribe",
    "baseten": "https://docs.baseten.co/inference/function-calling.md",
    "lmstudio": "https://lmstudio.ai/docs/app/api/endpoints/openai",
    "reasoning": "https://docs.baseten.co/inference/model-apis/reasoning",
}


def load_env() -> dict[str, str]:
    env = dict(os.environ)
    path = ROOT / ".env"
    if path.exists():
        for line in path.read_text().splitlines():
            if "=" in line and not line.lstrip().startswith("#"):
                k, v = line.split("=", 1)
                env.setdefault(k.strip(), v.strip().strip('"').strip("'"))
    return env


ENV = load_env()


def key(name: str) -> str | None:
    v = ENV.get(name)
    return v or None


def sample_frame() -> bytes:
    """A real frame from the room walkthrough (outside the repo), or any JPEG passed in PROBE_IMAGE."""
    p = Path(ENV.get("PROBE_IMAGE") or Path.home() / "Documents/projects/recall-scans/room1/0010.jpg")
    return p.read_bytes()


def timed(fn):
    t0 = time.perf_counter()
    try:
        out = fn()
        return out, round((time.perf_counter() - t0) * 1000)
    except Exception as e:  # noqa: BLE001 - a probe reports any failure instead of crashing the run
        return {"ok": False, "error": f"{type(e).__name__}: {e}"[:300]}, round((time.perf_counter() - t0) * 1000)


def http_error(r: httpx.Response) -> dict:
    body = r.text[:300].replace(key("META_MUSE_API_KEY") or "\0", "***").replace(key("BASETEN_API_KEY") or "\0", "***")
    return {"ok": False, "status": r.status_code, "body": body}


def meta_headers() -> dict[str, str]:
    return {"Authorization": f"Bearer {key('META_MUSE_API_KEY')}"}


def probe_meta_models() -> dict:
    r = httpx.get(f"{META}/models", headers=meta_headers(), timeout=30)
    if r.status_code != 200:
        return http_error(r)
    ids = [m.get("id") for m in r.json().get("data", [])]
    return {"ok": True, "models": ids}


def probe_meta_chat_tools() -> dict:
    body = {"model": "muse-spark-1.1", "messages": [{"role": "user", "content": "Where are my keys?"}],
            "tools": TOOLS[:1], "tool_choice": "auto", "max_tokens": 200}
    r = httpx.post(f"{META}/chat/completions", headers=meta_headers(), json=body, timeout=60)
    if r.status_code != 200:
        return http_error(r)
    msg = r.json()["choices"][0]["message"]
    calls = msg.get("tool_calls") or []
    return {"ok": True, "model": r.json().get("model"), "tool_calls": [c["function"] for c in calls],
            "text": (msg.get("content") or "")[:120]}


def probe_spark_vision() -> dict:
    img = base64.b64encode(sample_frame()).decode()
    body = {"model": "muse-spark-1.1", "max_tokens": 400, "messages": [{"role": "user", "content": [
        {"type": "text", "text": "Is a laptop visible in this photo? Answer yes, no or unsure."},
        {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{img}"}}]}]}
    r = httpx.post(f"{META}/chat/completions", headers=meta_headers(), json=body, timeout=60)
    if r.status_code != 200:
        return http_error(r)
    choice = r.json()["choices"][0]
    answer = (choice["message"].get("content") or "").strip()
    return {"ok": bool(answer), "answer": answer[:60], "finish_reason": choice.get("finish_reason")}


def probe_sam() -> dict:
    img = base64.b64encode(sample_frame()).decode()
    body = {"model": "sam-3.1", "metadata": {"include_confidence": "true"},
            "input": [{"role": "user", "content": [{"type": "input_text", "text": "laptop"},
                                                   {"type": "input_image",
                                                    "image_url": f"data:image/jpeg;base64,{img}"}]}]}
    r = httpx.post(f"{META}/responses", headers=meta_headers(), json=body, timeout=120)
    if r.status_code != 200:
        return http_error(r)
    data = r.json()
    texts = [c.get("text", "") for o in data.get("output", []) for c in (o.get("content") or [])
             if c.get("type") == "output_text"]
    text = "\n".join(texts)
    boxes = text.count("<|box;")
    masks = text.count("<|mask;")
    enc = text.split("data=", 1)[1].split(",", 2)[2][:1] if "data=" in text else None
    return {"ok": True, "output_keys": sorted({o.get("type") for o in data.get("output", [])}),
            "boxes": boxes, "masks": masks, "mask_marker": enc,
            "first_line_head": text.split("\n", 1)[0][:220]}


def probe_transcribe() -> dict:
    with tempfile.TemporaryDirectory() as d:
        wav = Path(d) / "q.wav"
        # macOS's built-in voice makes the test clip (an OS feature, not part of the product)
        subprocess.run(["say", "-o", str(wav), "--file-format=WAVE", "--data-format=LEI16@16000",
                        "Where did I leave my keys?"], check=True)
        audio = wav.read_bytes()
    out = {}
    for mode in ("PUSH_TO_TALK", "ENDPOINTING"):
        files = {"request": (None, json.dumps({"model": "muse-voice-transcribe-1.0", "audioEncoding": "WAV",
                                               "mode": mode}), "application/json"),
                 "audio": ("q.wav", audio, "audio/wav")}
        t0 = time.perf_counter()
        r = httpx.post(f"{META}/asr/transcribe", headers=meta_headers(), files=files, timeout=60)
        ms = round((time.perf_counter() - t0) * 1000)
        if r.status_code != 200:
            out[mode] = http_error(r)
        else:
            j = r.json()
            out[mode] = {"transcript": j.get("transcript"), "turns": len(j.get("turns") or []), "ms": ms}
    return {"ok": all("transcript" in v for v in out.values()), **out}


def _baseten(messages: list[dict], tools: list[dict] | None, max_tokens: int = 1000, **extra) -> dict:
    """One chat completion on Muse Spark Open via Baseten (BASETEN_BASE_URL, BASETEN_MODEL; Bearer key)."""
    base = (key("BASETEN_BASE_URL") or BASETEN).rstrip("/")
    model = key("BASETEN_MODEL") or "meta-models/muse-spark-open-1026"
    body = {"model": model, "messages": messages, "max_tokens": max_tokens, **extra}
    if tools:
        body |= {"tools": tools, "tool_choice": "auto"}
    r = httpx.post(f"{base}/chat/completions", headers={"Authorization": f"Bearer {key('BASETEN_API_KEY')}"}, json=body,
                   timeout=120)  # fmt: skip
    if r.status_code != 200:
        return http_error(r)
    choice = r.json()["choices"][0]
    usage = r.json().get("usage") or {}
    reasoning = (usage.get("completion_tokens_details") or {}).get("reasoning_tokens")
    return {"ok": True, "model": model, "finish_reason": choice.get("finish_reason"), "message": choice["message"],
            "reasoning_tokens": reasoning}


def probe_spark_open_plain() -> dict:
    out = _baseten([{"role": "user", "content": "Say hello in five words."}], None)
    if out.get("ok"):
        msg = out.pop("message")
        out["text"] = (msg.get("content") or "")[:120]
        out["reasoning_chars"] = len(msg.get("reasoning_content") or "")  # it reasons before answering
        out["ok"] = bool(out["text"]) and out["finish_reason"] == "stop"
    return out


def probe_spark_open() -> dict:
    out = _baseten([{"role": "system", "content": "You find objects in the user's home. Always use the tools."},
                    {"role": "user", "content": "Where are my keys?"}], TOOLS[:1])  # fmt: skip
    if out.get("ok"):
        msg = out.pop("message")
        out["tool_calls"] = [c["function"] for c in msg.get("tool_calls") or []]
        out["ok"] = bool(out["tool_calls"]) and out["finish_reason"] == "tool_calls"
    return out


def probe_spark_open_effort() -> dict:
    """The find_object call at Baseten's default reasoning effort (xhigh) vs "low", three times each."""
    messages = [{"role": "system", "content": "You find objects in the user's home. Always use the tools."},
                {"role": "user", "content": "Where are my keys?"}]  # fmt: skip
    out: dict = {}
    for effort in (None, "low"):
        runs = []
        for _ in range(3):
            t0 = time.perf_counter()
            r = _baseten(messages, TOOLS[:1], **({"reasoning_effort": effort} if effort else {}))
            ms = int((time.perf_counter() - t0) * 1000)
            if not r.get("ok"):
                out[effort or "default"] = r
                break
            calls = [c["function"]["name"] for c in r["message"].get("tool_calls") or []]
            runs.append({"ms": ms, "reasoning_tokens": r["reasoning_tokens"], "tool": calls[0] if calls else None})
        else:
            out[effort or "default"] = {"median_ms": sorted(x["ms"] for x in runs)[1], "runs": runs}
    # the last step: phrase a spoken answer from tool results (this is where the model reasons most)
    found = {"matches": [{"object_id": "ob_1", "label": "keys", "seen_when": "today at 18:02"}]}
    where = {"label": "keys", "room": "living room", "landmark": "desk", "relation": "on", "height_band": "waist",
             "seen_when": "today at 18:02"}  # fmt: skip
    call = {"id": "c1", "type": "function", "function": {"name": "find_object", "arguments": '{"name": "keys"}'}}
    call2 = {"id": "c2", "type": "function", "function": {"name": "describe_location", "arguments": '{"object_id": "ob_1"}'}}
    phrase = messages + [{"role": "assistant", "content": "", "tool_calls": [call]},
                         {"role": "tool", "tool_call_id": "c1", "content": json.dumps(found)},
                         {"role": "assistant", "content": "", "tool_calls": [call2]},
                         {"role": "tool", "tool_call_id": "c2", "content": json.dumps(where)}]  # fmt: skip
    for effort in (None, "low"):
        runs = []
        for _ in range(3):
            t0 = time.perf_counter()
            r = _baseten(phrase, TOOLS[:2], **({"reasoning_effort": effort} if effort else {}))
            ms = int((time.perf_counter() - t0) * 1000)
            if not r.get("ok"):
                runs.append({"error": r})
                break
            runs.append({"ms": ms, "reasoning_tokens": r["reasoning_tokens"], "text": (r["message"].get("content") or "")[:90]})
        ok = [x for x in runs if "ms" in x]
        out[f"phrase_{effort or 'default'}"] = {"median_ms": sorted(x["ms"] for x in ok)[len(ok) // 2] if ok else None,
                                                "runs": runs}  # fmt: skip
    low, default = out.get("low", {}), out.get("default", {})
    out["ok"] = all(x["tool"] == "find_object" for x in low.get("runs", [])) and "median_ms" in default
    return out


def probe_lmstudio() -> dict:
    base = key("LMSTUDIO_BASE_URL") or "http://localhost:1234/v1"
    try:
        r = httpx.get(f"{base}/models", timeout=3)
    except httpx.HTTPError:
        return {"ok": False, "skipped": "LM Studio server is not running (lms server start)"}
    ids = [m["id"] for m in r.json().get("data", [])]
    glimmer = [i for i in ids if "glimmer" in i.lower()]
    if not glimmer:
        return {"ok": False, "skipped": "no Glimmer model loaded in LM Studio", "models": ids}
    body = {"model": glimmer[0], "messages": [{"role": "user", "content": "Where are my keys?"}],
            "tools": TOOLS[:1], "max_tokens": 200}
    r = httpx.post(f"{base}/chat/completions", json=body, timeout=180)
    if r.status_code != 200:
        return http_error(r)
    msg = r.json()["choices"][0]["message"]
    return {"ok": True, "model": glimmer[0], "tool_calls": [c["function"] for c in msg.get("tool_calls") or []]}


PROBES = [
    ("Meta Model API: models list", "META_MUSE_API_KEY", probe_meta_models, DOCS["models"]),
    ("Muse Spark 1.1: chat with find_object tool", "META_MUSE_API_KEY", probe_meta_chat_tools, DOCS["meta"]),
    ("Muse Spark 1.1: image input", "META_MUSE_API_KEY", probe_spark_vision, DOCS["vision"]),
    ("SAM 3.1: one frame, prompt 'laptop'", "META_MUSE_API_KEY", probe_sam, DOCS["sam"]),
    ("Muse Voice Transcribe: 2 s WAV, both modes", "META_MUSE_API_KEY", probe_transcribe, DOCS["asr"]),
    ("spark_open_baseten: plain reply", "BASETEN_API_KEY", probe_spark_open_plain, DOCS["baseten"]),
    ("spark_open_baseten: find_object tool call", "BASETEN_API_KEY", probe_spark_open, DOCS["baseten"]),
    ("spark_open_baseten: reasoning_effort default vs low", "BASETEN_API_KEY", probe_spark_open_effort,
     DOCS["reasoning"]),
    ("Muse Glimmer on LM Studio: find_object tool", None, probe_lmstudio, DOCS["lmstudio"]),
]


def main() -> int:
    only = set(sys.argv[1:])
    rows = []
    for name, needs, fn, doc in PROBES:
        if only and not any(o.lower() in name.lower() for o in only):
            continue
        if needs and not key(needs):
            result, ms = {"ok": False, "skipped": f"{needs} is not set in .env"}, 0
        else:
            result, ms = timed(fn)
        status = "PASS" if result.get("ok") else ("SKIP" if "skipped" in result else "FAIL")
        print(f"{status:4}  {ms:>6} ms  {name}")
        print("      " + json.dumps({k: v for k, v in result.items() if k != "ok"})[:600])
        rows.append((name, status, ms, result, doc))
    stamp = datetime.now(UTC).strftime("%Y-%m-%d %H:%M UTC")
    lines = [f"\n## Probes, {stamp} (`make probes`, real calls)\n", "| Probe | Result | Time | What came back | Docs |",
             "|---|---|---|---|---|"]
    for name, status, ms, result, doc in rows:
        detail = json.dumps({k: v for k, v in result.items() if k != "ok"}).replace("|", "\\|")[:400]
        lines.append(f"| {name} | {status} | {ms} ms | `{detail}` | {doc} |")
    with VERIFICATION.open("a") as f:
        f.write("\n".join(lines) + "\n")
    return 0 if all(s != "FAIL" for _, s, *_ in rows) else 1


if __name__ == "__main__":
    sys.exit(main())
