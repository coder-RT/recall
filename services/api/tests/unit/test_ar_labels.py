"""Labels over the camera: every thing in a room, placed in the ARKit frame of the room's newest scan."""

import numpy as np
import pytest

from recall_api.application.ar_labels import ArLabelsInRoom, NoRoomScan
from recall_api.application.list_things import ListThings
from recall_api.application.trust import TrustPolicy
from tests.unit.test_matching_and_ingest import ROOM, Repos, obj


def _room():
    r = Repos()
    r.scan("s1", 10)  # the Office
    wallet = obj("wallet", [3.0, 2.0, 0.4]) | {"sightings": 1}
    r.ingest("s1", {"room": ROOM, "landmarks": [obj("desk", [1.0, 1.0, 0.38])],
                    "objects": [obj("keys", [1.0, 1.0, 0.8]), wallet]})  # fmt: skip
    scan = r.scans.get("s1")
    # home = ARKit turned z-up and moved: ARKit (x, y, z) → home (x + 2, -z, y)
    T = np.array([[1, 0, 0, 2], [0, 0, -1, 0], [0, 1, 0, 0], [0, 0, 0, 1]], dtype=float)
    scan.transform_to_home = tuple(T.reshape(-1))
    r.scans.save(scan)
    return ArLabelsInRoom(ListThings(r.homes, r.objects, r.scans, TrustPolicy()), r.scans)


def test_each_thing_is_placed_in_the_rooms_ar_frame_with_its_trust():
    labels = _room()("flat", "Office")
    assert labels.scan_id == "s1" and labels.floor_y_arkit == 0.0
    by = {x.title.split()[-1]: x for x in labels.labels}
    assert by["keys"].position_arkit == (-1.0, 0.8, -1.0)  # home (1, 1, 0.8) back in ARKit
    assert by["keys"].trusted and not by["keys"].needs_review
    assert (by["wallet"].trusted, by["wallet"].photos) == (False, 1)  # seen once: red on the phone
    assert by["keys"].place.endswith("at waist height")


def test_a_room_never_scanned_has_no_labels():
    with pytest.raises(NoRoomScan):
        _room()("flat", "Kitchen")
