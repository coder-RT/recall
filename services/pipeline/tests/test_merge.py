import numpy as np

from recall_pipeline.domain.merge import Piece, merge


def _p(label, lo, hi, conf=0.8, n=1):
    return Piece(label, np.array(lo, float), np.array(hi, float), conf, n, 0, np.zeros((1, 3)))


def test_table_and_desk_boxes_of_one_desk_become_one_landmark():
    desk = _p("desk", [0, 0, 0], [1.2, 0.6, 0.75], conf=0.9, n=3)
    table = _p("table", [0.1, 0.05, 0], [1.1, 0.6, 0.76], conf=0.6, n=1)
    part = _p("desk", [1.25, 0, 0.2], [1.6, 0.6, 0.75], n=2)  # a part seen from the side, 5 cm away
    ((merged, names),) = merge([desk, table, part])
    assert names == ["desk", "table"] and merged.sightings == 6
    assert np.allclose(merged.lo, [0, 0, 0]) and np.allclose(merged.hi, [1.6, 0.6, 0.76])


def test_different_kinds_and_far_pieces_stay_apart():
    desk = _p("desk", [0, 0, 0], [1, 1, 0.75])
    tv = _p("tv", [0.2, 0.2, 0.75], [0.8, 0.4, 1.2])  # on the desk: a different kind
    other = _p("desk", [3, 0, 0], [4, 1, 0.75])  # another desk across the room
    assert len(merge([desk, tv, other])) == 3
