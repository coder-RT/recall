"""The warm server's model: loaded once, reused, dropped after the idle time."""

from recall_pipeline.adapters.serve import WarmModel


def test_loads_once_and_unloads_when_idle():
    loads = []
    m = WarmModel(lambda: loads.append(1) or object(), idle=600)
    assert not m.loaded
    a, b = m.get(), m.get()
    assert a is b and len(loads) == 1
    assert not m.unload_if_idle()  # just used
    assert m.unload_if_idle(now=10**9)  # long unused
    assert not m.loaded
    m.get()
    assert len(loads) == 2
