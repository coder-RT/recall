"""SAM calls start before the reconstruction and come back in prompt order."""

import threading
import time
from concurrent.futures import ThreadPoolExecutor

from recall_pipeline.application.ports import Box
from recall_pipeline.application.process_episode import start_sam


class Photos:
    def jpeg(self, i: int) -> bytes:
        return f"frame{i}".encode()


class SlowSam:
    """Blocks every call until released, so the test can see that start_sam didn't wait."""

    def __init__(self) -> None:
        self.go = threading.Event()
        self.started = 0
        self.lock = threading.Lock()

    def boxes(self, jpeg: bytes, concept: str) -> list[Box]:
        with self.lock:
            self.started += 1
        self.go.wait(5)
        return [Box(concept, 0.9, (0, 0, 1, 1))] if jpeg == b"frame3" else []


def test_calls_are_in_flight_before_start_sam_returns_and_keep_prompt_order():
    sam = SlowSam()
    with ThreadPoolExecutor(4) as pool:
        t = time.perf_counter()
        pending = start_sam(pool, sam, Photos(), [0, 3], ("sofa", "keys", "mug"))
        assert time.perf_counter() - t < 0.5  # returned without waiting for any answer
        assert sorted(pending) == [0, 3]
        deadline = time.perf_counter() + 2
        while sam.started < 4 and time.perf_counter() < deadline:
            time.sleep(0.01)
        assert sam.started == 4  # as many in flight as the pool allows, while "reconstruction" would run
        sam.go.set()
        assert [[b.label for b in f.result()] for f in pending[3]] == [["sofa"], ["keys"], ["mug"]]
        assert all(f.result() == [] for f in pending[0])
