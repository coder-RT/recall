"""recall-pipeline: process one episode folder and post the results to the API."""

from __future__ import annotations

import argparse
import logging
import sys


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="recall-pipeline")
    sub = p.add_subparsers(dest="cmd", required=True)
    proc = sub.add_parser("process", help="reconstruct, segment and post one episode")
    proc.add_argument("episode_dir")
    proc.add_argument("--scan-id", required=True)
    proc.add_argument("--no-post", action="store_true", help="write result.json only; don't post to the API")
    proc.add_argument("--out", help="where to write the result (default: <episode>/result.json)")
    args = p.parse_args(argv)
    fmt = "%(asctime)s %(levelname)s %(message)s"
    logging.basicConfig(level=logging.INFO, format=fmt, stream=sys.stdout, force=True)
    logging.getLogger("httpx").setLevel(logging.WARNING)  # one line per SAM call is noise; failures still show
    sys.stdout.reconfigure(line_buffering=True)  # type: ignore[union-attr]  # the API's log file shows progress live
    if args.cmd == "process":
        from recall_pipeline.adapters.run import process  # heavy imports (torch) only when processing

        return process(args.episode_dir, args.scan_id, post=not args.no_post, out=args.out)
    return 2


if __name__ == "__main__":
    sys.exit(main())
