"""The warm server's model: loaded once, reused, dropped after the idle time."""

import sys
import types

from recall_pipeline.adapters.serve import WarmModel, free_gpu_cache


def test_loads_once_and_unloads_when_idle():
    loads, freed = [], []
    m = WarmModel(lambda: loads.append(1) or object(), idle=600, free_cache=lambda: freed.append(1))
    assert not m.loaded
    a, b = m.get(), m.get()
    assert a is b and len(loads) == 1
    assert not m.unload_if_idle()  # just used
    assert m.unload_if_idle(now=10**9)  # long unused
    assert not m.loaded and freed == [1]
    m.get()
    assert len(loads) == 2


def _fake_torch(monkeypatch, mps: bool) -> list[int]:
    emptied: list[int] = []
    torch = types.SimpleNamespace(
        backends=types.SimpleNamespace(mps=types.SimpleNamespace(is_available=lambda: mps)),
        mps=types.SimpleNamespace(empty_cache=lambda: emptied.append(1)),
    )
    monkeypatch.setitem(sys.modules, "torch", torch)
    return emptied


def test_gpu_cache_is_left_alone_without_mps(monkeypatch):
    # Linux CI or Modal: calling empty_cache there can end the process with a signal.
    emptied = _fake_torch(monkeypatch, mps=False)
    free_gpu_cache()
    assert emptied == []


def test_gpu_cache_is_emptied_on_a_mac(monkeypatch):
    emptied = _fake_torch(monkeypatch, mps=True)
    free_gpu_cache()
    assert emptied == [1]
