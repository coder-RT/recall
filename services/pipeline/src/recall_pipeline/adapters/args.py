"""The command line's arguments, shared by `recall-pipeline` and the warm server's jobs."""

from __future__ import annotations

import argparse


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="recall-pipeline")
    sub = p.add_subparsers(dest="cmd", required=True)
    proc = sub.add_parser("process", help="reconstruct, segment and post one episode")
    proc.add_argument("episode_dir")
    proc.add_argument("--scan-id", required=True)
    proc.add_argument("--no-post", action="store_true", help="write result.json only; don't post to the API")
    proc.add_argument("--out", help="where to write the result (default: <episode>/result.json)")
    serve = sub.add_parser("serve", help="keep MapAnything loaded and run jobs sent by the API's worker")
    serve.add_argument("--port", type=int, default=8766)
    serve.add_argument("--idle-minutes", type=float, default=10, help="unload the model after this long unused")
    return p
