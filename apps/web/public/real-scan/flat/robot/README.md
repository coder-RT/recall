# Living room: Recall robot package

From Recall's memory of this room (scan bb449f4c-813f-42f7-9c24-0e09d58acfea, made 2026-11-01 23:27 UTC). Geometry and labels
only: no photos, no video, nothing the owner said.

All positions are in the `map` frame: metres, the floor at z = 0, z up.

| File | What it is |
|---|---|
| `map.yaml`, `map.pgm` | 2D occupancy map for the Nav2 map server: 60 x 91 cells of 0.1 m |
| `objects.json` | 17 things and 26 pieces of furniture: label, colour, position, size |
| `room.json` | The room's floor outline, walls and furniture boxes |
| `cloud.ply` | 67744 3D points (x y z), to plan reaching a thing at its height |

A robot with the robot key can fetch a fresh copy from the owner's Mac while robot access is on:
`GET /homes/flat/robot-package?room=Living room`. Recall finds things; it doesn't move them.
