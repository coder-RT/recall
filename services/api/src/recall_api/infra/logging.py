"""Logging setup. Never log keys, audio, images or the user's position."""

import logging


def configure(level: int = logging.INFO) -> None:
    logging.basicConfig(level=level, format="%(asctime)s %(levelname)s %(name)s %(message)s")
