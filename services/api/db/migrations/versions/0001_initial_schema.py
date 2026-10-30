"""Initial schema: homes, scans, keyframes, landmarks, objects, observations (metres, home frame, z up).

Revision ID: 0001
"""

from alembic import op

revision = "0001"
down_revision = None

SQL = """
CREATE TABLE homes (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  floor_plane TEXT,
  room_model TEXT,
  first_scan_id TEXT,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);
CREATE TABLE scans (
  id TEXT PRIMARY KEY,
  home_id TEXT NOT NULL REFERENCES homes(id),
  room TEXT NOT NULL,
  created_at TEXT NOT NULL,
  status TEXT NOT NULL,
  detail TEXT,
  archive_size INTEGER NOT NULL,
  archive_sha256 TEXT NOT NULL,
  part_size INTEGER NOT NULL,
  frame_count INTEGER,
  object_count INTEGER,
  transform_to_home TEXT,
  manifest_uri TEXT
);
CREATE INDEX scans_home ON scans(home_id);
CREATE TABLE keyframes (
  id TEXT PRIMARY KEY,
  scan_id TEXT NOT NULL REFERENCES scans(id),
  idx INTEGER NOT NULL,
  ts REAL NOT NULL,
  image_uri TEXT NOT NULL,
  depth_uri TEXT,
  pose_4x4 TEXT NOT NULL,
  tracking_state TEXT NOT NULL
);
CREATE TABLE landmarks (
  id TEXT PRIMARY KEY,
  home_id TEXT NOT NULL REFERENCES homes(id),
  label TEXT NOT NULL,
  bbox_min TEXT NOT NULL,
  bbox_max TEXT NOT NULL,
  centroid TEXT NOT NULL,
  room TEXT,
  front_dir TEXT
);
CREATE INDEX landmarks_home ON landmarks(home_id);
CREATE TABLE objects (
  id TEXT PRIMARY KEY,
  home_id TEXT NOT NULL REFERENCES homes(id),
  label TEXT NOT NULL,
  aliases TEXT NOT NULL DEFAULT '[]'
);
CREATE INDEX objects_home ON objects(home_id);
CREATE TABLE observations (
  id TEXT PRIMARY KEY,
  object_id TEXT NOT NULL REFERENCES objects(id),
  scan_id TEXT NOT NULL REFERENCES scans(id),
  keyframe_index INTEGER,
  ts TEXT NOT NULL,
  x REAL NOT NULL,
  y REAL NOT NULL,
  z REAL NOT NULL,
  confidence REAL NOT NULL,
  crop_uri TEXT,
  stale INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX observations_object ON observations(object_id);
"""


def upgrade() -> None:
    for stmt in filter(str.strip, SQL.split(";")):
        op.execute(stmt)


def downgrade() -> None:
    for table in ("observations", "objects", "landmarks", "keyframes", "scans", "homes"):
        op.execute(f"DROP TABLE {table}")
