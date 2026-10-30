from recall_api.domain.memory import BBox, Landmark, Position
from recall_api.domain.spatial import HeightBand, height_band, relate, shelf_level


def desk(front=(0.0, -1.0)):
    return Landmark(
        id="lm1",
        label="desk",
        bbox=BBox(Position(0, 0, 0), Position(1.2, 0.6, 0.76)),
        centroid=Position(0.6, 0.3, 0.38),
        front_dir=front,
    )


def test_height_bands_follow_the_thresholds():
    assert [height_band(z) for z in (0.1, 0.5, 0.9, 1.3, 1.7)] == [
        HeightBand.FLOOR,
        HeightBand.KNEE,
        HeightBand.WAIST,
        HeightBand.CHEST,
        HeightBand.HEAD,
    ]
    assert height_band(0.3) == HeightBand.KNEE  # edges belong to the band above


def test_an_object_resting_on_the_top_surface_is_on_it():
    r = relate(Position(0.4, 0.3, 0.80), [desk()])
    assert r.kind == "on" and r.landmark.label == "desk" and r.band == HeightBand.WAIST


def test_left_and_right_are_as_seen_by_someone_facing_the_landmarks_front():
    # the desk's front faces −y; a person standing there faces +y, so their left is −x
    assert relate(Position(-0.4, 0.3, 0.2), [desk()]).kind == "left_of"
    assert relate(Position(1.6, 0.3, 0.2), [desk()]).kind == "right_of"


def test_far_from_every_landmark_means_room_only():
    r = relate(Position(5, 5, 0.1), [desk()])
    assert r.landmark is None and r.kind is None


def test_shelf_level_counts_from_the_bottom():
    assert shelf_level(0.82, [0.40, 0.80, 1.20]) == 2
    assert shelf_level(0.10, [0.40, 0.80]) is None
