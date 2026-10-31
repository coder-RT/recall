"""recall-pipeline: process one episode folder and post the results to the API."""

from __future__ import annotations

import logging
import sys

from recall_pipeline.adapters.args import parser


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    fmt = "%(asctime)s %(levelname)s %(message)s"
    logging.basicConfig(level=logging.INFO, format=fmt, stream=sys.stdout, force=True)
    logging.getLogger("httpx").setLevel(logging.WARNING)  # one line per SAM call is noise; failures still show
    sys.stdout.reconfigure(line_buffering=True)  # type: ignore[union-attr]  # the API's log file shows progress live
    if args.cmd == "process":
        from recall_pipeline.adapters.run import process  # heavy imports (torch) only when processing

        return process(args.episode_dir, args.scan_id, post=not args.no_post, out=args.out)
    if args.cmd == "serve":
        from recall_pipeline.adapters.serve import serve

        return serve(args.port, args.idle_minutes * 60)
    return 2


if __name__ == "__main__":
    sys.exit(main())
