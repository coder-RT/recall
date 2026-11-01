import numpy as np

from recall_pipeline.domain.merge import ObjectCluster, merge_objects


def mug(x: float, frames: range | set[int], color: str | None = "white") -> ObjectCluster:
    return ObjectCluster(np.array([x, 0.0, 0.8]), color, set(frames))


def test_a_loop_walk_seeing_one_mug_twice_keeps_one_mug():
    # seen at the start and again on the way back, 30 cm apart after the phone's drift
    assert merge_objects([mug(0.0, range(1, 11)), mug(0.3, range(50, 61))], 0.45) == [[0, 1]]


def test_two_mugs_in_one_photo_stay_two():
    assert len(merge_objects([mug(0.0, {11, 12}), mug(0.3, {12, 13})], 0.45)) == 2


def test_a_red_mug_and_a_white_mug_stay_two():
    assert len(merge_objects([mug(0.0, {1}, "red"), mug(0.3, {50}, "white")], 0.45)) == 2


def test_an_unknown_colour_doesnt_keep_them_apart():
    assert len(merge_objects([mug(0.0, {1}, None), mug(0.3, {50}, "white")], 0.45)) == 1


def test_mugs_a_metre_apart_stay_two():
    assert len(merge_objects([mug(0.0, {1}), mug(1.0, {50})], 0.45)) == 2


def test_two_mugs_from_one_photo_never_end_up_merged_through_a_third_cluster():
    # 0 and 2 share photo 1, so they're two mugs; 1 (seen alone) may join either, never both
    groups = merge_objects([mug(0.0, {1}), mug(0.2, {50}), mug(0.35, {1, 70})], 0.45)
    assert len(groups) == 2
    assert not any({0, 2} <= set(g) for g in groups)
