import numpy as np

from recall_pipeline.domain.appearance import dominant_color, pixel_names, vote


def test_basic_colours():
    rgb = np.array(
        [[10, 10, 10], [250, 250, 250], [128, 128, 128], [220, 30, 30], [30, 160, 40], [30, 60, 200],
         [240, 220, 40], [110, 70, 30], [225, 205, 170], [140, 40, 180], [240, 120, 190], [245, 140, 20]],
        dtype=np.uint8,
    )  # fmt: skip
    expected = ["black", "white", "grey", "red", "green", "blue"]
    expected += ["yellow", "brown", "beige", "purple", "pink", "orange"]
    assert pixel_names(rgb).tolist() == expected


def test_dominant_colour_ignores_the_box_edges():
    img = np.full((100, 100, 3), 250, np.uint8)  # white wall
    img[30:70, 30:70] = (30, 60, 200)  # a blue bag in the middle of a loose box
    assert dominant_color(img, (10, 10, 90, 90)) == "blue"


def test_vote_weights_by_score():
    assert vote([("red", 0.9), ("brown", 0.5), ("brown", 0.3)]) == "red"
    assert vote([(None, 1.0)]) is None
