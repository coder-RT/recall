"""recall-pipeline: process one episode folder and post the results to the API."""

from __future__ import annotations

import argparse
import sys


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="recall-pipeline")
    sub = p.add_subparsers(dest="cmd", required=True)
    proc = sub.add_parser("process", help="reconstruct, segment and post one episode")
    proc.add_argument("episode_dir")
    proc.add_argument("--scan-id", required=True)
    args = p.parse_args(argv)
    if args.cmd == "process":
        from recall_pipeline.adapters.run import process  # heavy imports (torch) only when processing

        return process(args.episode_dir, args.scan_id)
    return 2


if __name__ == "__main__":
    sys.exit(main())
