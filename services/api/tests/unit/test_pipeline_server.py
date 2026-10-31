"""Jobs go to the warm pipeline when it runs; otherwise the caller falls back to a fresh process."""

import json
import socket
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer

from recall_api.infra.pipeline_server import PipelineServer


def _free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def test_down_means_run_it_as_a_process():
    assert PipelineServer(f"http://127.0.0.1:{_free_port()}", "k").run(["ep", "--scan-id", "s"], "/tmp/x.log") is None


def test_up_runs_the_job_there_with_the_device_key():
    seen: list[dict] = []

    class Fake(BaseHTTPRequestHandler):
        def _ok(self, body: dict) -> None:
            data = json.dumps(body).encode()
            self.send_response(200)
            self.send_header("content-length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):  # noqa: N802
            self._ok({"loaded": True, "busy": False})

        def do_POST(self):  # noqa: N802
            body = json.loads(self.rfile.read(int(self.headers["content-length"])))
            seen.append({"path": self.path, "key": self.headers.get("x-device-key"), **body})
            self._ok({"code": 0})

        def log_message(self, *a):
            pass

    port = _free_port()
    httpd = HTTPServer(("127.0.0.1", port), Fake)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    try:
        code = PipelineServer(f"http://127.0.0.1:{port}", "k").run(["ep", "--scan-id", "s"], "/tmp/x.log")
    finally:
        httpd.shutdown()
    assert code == 0
    assert seen == [{"path": "/jobs", "key": "k", "args": ["ep", "--scan-id", "s"], "log": "/tmp/x.log"}]
