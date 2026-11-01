"""`recall-pipeline serve`: the pipeline kept warm. MapAnything loads once (about 20 s with Python and torch) instead of
once per scan; jobs run one at a time, as before. Local only (127.0.0.1), and each request carries the device key.

    GET  /health  -> {"loaded": bool, "busy": bool}
    POST /warm    -> starts loading the model (a scan is uploading), returns at once
    POST /jobs    {"args": [...process args...], "log": "<file>"} -> runs the job, returns {"code": int} when done

The model is unloaded after `idle` seconds unused, so the Mac's memory is free again (CLAUDE.md: never alongside LM
Studio)."""

from __future__ import annotations

import contextlib
import gc
import hmac
import json
import logging
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from recall_pipeline.adapters.run import ROOT, _env

log = logging.getLogger("recall_pipeline.serve")
MAX_JOB_BYTES = 64 * 1024  # a job is a few arguments and a path


def free_gpu_cache() -> None:
    """Return the Apple GPU's cached memory, only where there is one. `torch.mps.empty_cache()` on a machine without
    MPS can kill the process with a signal, which no `try` catches, so the check comes first."""
    try:
        import torch
    except ImportError:
        return
    if torch.backends.mps.is_available():
        torch.mps.empty_cache()


class WarmModel:
    """The loaded reconstructor, loaded on first use and dropped after `idle` seconds without a job."""

    def __init__(self, load, idle: float, free_cache=None) -> None:
        self._load, self.idle = load, idle
        self._free_cache = free_cache or free_gpu_cache
        self._model = None
        self._used = time.monotonic()
        self._lock = threading.Lock()

    @property
    def loaded(self) -> bool:
        return self._model is not None

    def get(self):
        with self._lock:
            if self._model is None:
                t = time.perf_counter()
                self._model = self._load()
                log.info("model loaded in %.1f s", time.perf_counter() - t)
            self._used = time.monotonic()
            return self._model

    def touch(self) -> None:
        self._used = time.monotonic()

    def unload_if_idle(self, now: float | None = None) -> bool:
        with self._lock:
            if self._model is None or (now or time.monotonic()) - self._used < self.idle:
                return False
            self._model = None
        gc.collect()
        self._free_cache()
        log.info("model unloaded after %.0f min idle", self.idle / 60)
        return True


def _load():
    from recall_pipeline.adapters.run import make_reconstructor

    return make_reconstructor(_env())


def data_dir() -> Path:
    return Path(_env().get("RECALL_DATA_DIR") or ROOT / "data").resolve()


def run_job(model: WarmModel, args: list[str], log_file: Path) -> int:
    """One `process` job with the warm model; its log and printed summary go to the job's log file, as before."""
    from recall_pipeline.adapters.args import parser
    from recall_pipeline.adapters.run import process

    a = parser().parse_args(["process", *args])
    episode = Path(a.episode_dir).resolve()
    data = data_dir()
    # every path a job reads or writes stays inside the data folder: the episode, its log, and any --out
    for what, path in (
        ("episode", episode),
        ("log", log_file.resolve()),
        ("out", Path(a.out).resolve() if a.out else None),
    ):
        if path is not None and data not in path.parents:
            log.warning("refused: the %s %s is outside the data folder", what, path)
            return 2
    log_file.parent.mkdir(parents=True, exist_ok=True)
    with log_file.open("a", buffering=1) as out, contextlib.redirect_stdout(out):
        handler = logging.StreamHandler(out)
        handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
        logging.getLogger().addHandler(handler)
        try:
            return process(str(episode), a.scan_id, post=not a.no_post, out=a.out, recon=model.get())
        except Exception:
            logging.getLogger("recall_pipeline").exception("job failed")
            return 1
        finally:
            logging.getLogger().removeHandler(handler)
            model.touch()


def make_server(port: int, model: WarmModel, key: str) -> ThreadingHTTPServer:
    """The HTTP side (separate from `serve` so tests can start and stop it)."""
    jobs = threading.Lock()  # one job at a time: MapAnything needs most of the GPU memory

    class Handler(BaseHTTPRequestHandler):
        def _reply(self, code: int, body: dict) -> None:
            data = json.dumps(body).encode()
            self.send_response(code)
            self.send_header("content-type", "application/json")
            self.send_header("content-length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def _authorised(self) -> bool:
            if not key:  # never open: without a key nothing is served
                self._reply(503, {"error": "device key unset"})
                return False
            if not hmac.compare_digest(self.headers.get("x-device-key", "").encode(), key.encode()):
                self._reply(401, {"error": "device key"})
                return False
            return True

        def do_GET(self) -> None:  # noqa: N802
            if not self._authorised():
                return
            if self.path == "/health":
                self._reply(200, {"loaded": model.loaded, "busy": jobs.locked()})
            else:
                self._reply(404, {"error": "not found"})

        def do_POST(self) -> None:  # noqa: N802
            if not self._authorised():
                return
            if self.path == "/warm":
                threading.Thread(target=model.get, daemon=True).start()
                self._reply(202, {"loading": not model.loaded})
                return
            if self.path == "/jobs":
                size = int(self.headers.get("content-length", 0) or 0)
                if size > MAX_JOB_BYTES:
                    self._reply(413, {"error": "too large"})
                    return
                try:
                    body = json.loads(self.rfile.read(size) or b"{}")
                    args, log_path = [str(x) for x in body.get("args", [])], Path(str(body["log"]))
                except (ValueError, KeyError, TypeError):
                    self._reply(400, {"error": "args and log expected"})
                    return
                with jobs:
                    code = run_job(model, args, log_path)
                self._reply(200, {"code": code})
                return
            self._reply(404, {"error": "not found"})

        def log_message(self, *a) -> None:  # requests are logged by the jobs themselves
            pass

    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    server.jobs = jobs  # type: ignore[attr-defined]
    return server


def serve(port: int, idle: float, load=_load) -> int:
    model = WarmModel(load, idle)
    env = _env()
    server = make_server(port, model, env.get("RECALL_DEVICE_KEY", ""))

    def reaper() -> None:
        while True:
            time.sleep(30)
            if not server.jobs.locked():  # type: ignore[attr-defined]
                model.unload_if_idle()

    threading.Thread(target=reaper, daemon=True).start()
    log.info("pipeline server on 127.0.0.1:%d (model unloads after %.0f min idle)", port, idle / 60)
    server.serve_forever()
    return 0
