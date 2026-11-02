"""Construction-document style sheets of a regenerated room, as SVG (A3 landscape, millimetres).

A1.1 floor plan: wall poché (dashed where the scan never saw the wall), door swings, furniture outlines, numbered
things, a dimension string on every wall and overall, area and perimeter, scale bar, north (magnetic when the scan
had a reliable compass), title block.
A2.1 interior elevations: each scanned wall seen square on, from the scan's own coloured points (nearest to the wall
wins), with floor, desk-height and ceiling levels and the wall's width. All text is real <text>, so the sheets are
searchable and readable by screen readers; nothing on them is generated, only measured and drawn.
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from html import escape

import numpy as np
from scipy import ndimage
from shapely.geometry import Polygon

from .architecture import WALL_T, Wall

PAPER_W, PAPER_H = 420.0, 297.0
AREA = (15.0, 15.0, 325.0, 282.0)  # drawing area: x0, y0, x1, y1 (the title block is to its right)
INK, MUTED, LINE, BLUE, CTA, PALE = "#1c1e21", "#4b4f56", "#bdc7d8", "#29487d", "#1f6516", "#dfe3ee"
FONT = "Atkinson Hyperlegible, Helvetica, Arial, sans-serif"


@dataclass(frozen=True)
class Sheet:
    id: str
    title: str
    svg: str
    summary: str  # one sentence for alt text


@dataclass(frozen=True)
class Furnishing:
    label: str
    lo: tuple[float, float, float]  # plan frame
    hi: tuple[float, float, float]


@dataclass(frozen=True)
class Item:
    number: int
    title: str  # "grey bag"
    place: str  # "near the desk, knee height"
    at: tuple[float, float, float]  # plan frame


def _t(
    x: float,
    y: float,
    text: str,
    size: float = 2.6,
    anchor: str = "middle",
    weight: str = "normal",
    fill: str = INK,
    rotate: float = 0.0,
) -> str:
    rot = f' transform="rotate({rotate:.1f} {x:.2f} {y:.2f})"' if rotate else ""
    return (
        f'<text x="{x:.2f}" y="{y:.2f}" font-size="{size}" text-anchor="{anchor}" font-weight="{weight}" '
        f'fill="{fill}"{rot}>{escape(text)}</text>'
    )


def _poly(points, fill: str = "none", stroke: str = INK, width: float = 0.25, dash: str = "") -> str:
    d = " ".join(f"{x:.2f},{y:.2f}" for x, y in points)
    dash_attr = f' stroke-dasharray="{dash}"' if dash else ""
    return f'<polygon points="{d}" fill="{fill}" stroke="{stroke}" stroke-width="{width}"{dash_attr}/>'


def _line(a, b, stroke: str = INK, width: float = 0.18, dash: str = "") -> str:
    dash_attr = f' stroke-dasharray="{dash}"' if dash else ""
    return (
        f'<line x1="{a[0]:.2f}" y1="{a[1]:.2f}" x2="{b[0]:.2f}" y2="{b[1]:.2f}" stroke="{stroke}" '
        f'stroke-width="{width}"{dash_attr}/>'
    )


def _sheet(sheet_id: str, title: str, room: str, captured: str, body: list[str], summary: str, notes: list[str]) -> str:
    """The paper, border and the title block down the right side (as on the screenshot's sheets)."""
    tb = 335.0
    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{PAPER_W:.0f}mm" height="{PAPER_H:.0f}mm" '
        f'viewBox="0 0 {PAPER_W:.0f} {PAPER_H:.0f}" font-family="{FONT}" role="img">',
        f"<title>{escape(f'{sheet_id} {title}: {room}')}</title><desc>{escape(summary)}</desc>",
        f'<rect width="{PAPER_W}" height="{PAPER_H}" fill="#ffffff"/>',
        f'<rect x="8" y="8" width="{PAPER_W - 16}" height="{PAPER_H - 16}" fill="none" '
        f'stroke="{INK}" stroke-width="0.5"/>',
        _line((tb, 8), (tb, PAPER_H - 8), width=0.5),
        *body,
    ]
    # title block: the Braille R (dots 1, 2, 3, 5), RECALL, the room, notes, the sheet title and number
    for n, (dx, dy) in enumerate([(0, 0), (0, 4), (0, 8), (4, 0), (4, 4), (4, 8)], start=1):
        on = n in (1, 2, 3, 5)
        parts.append(f'<circle cx="{tb + 10 + dx:.1f}" cy="{20 + dy:.1f}" r="1.5" fill="{BLUE if on else PALE}"/>')
    parts += [
        _t(tb + 20, 25, "RECALL", 6, "start", "bold"),
        _t(tb + 6, 40, room, 4.2, "start", "bold"),
        _t(tb + 6, 46, f"Scanned {captured}", 2.6, "start", fill=MUTED),
    ]
    y = 58.0
    for note in notes:
        for line in _wrap(note, 34):
            parts.append(_t(tb + 6, y, line, 2.3, "start", fill=MUTED))
            y += 3.3
        y += 1.5
    parts += [
        _line((tb, PAPER_H - 40), (PAPER_W - 8, PAPER_H - 40), width=0.35),
        _t(tb + 6, PAPER_H - 30, title, 4, "start", "bold"),
        _t(tb + 6, PAPER_H - 15, sheet_id, 9, "start", "bold"),
        "</svg>",
    ]
    return "\n".join(parts)


def _wrap(text: str, width: int) -> list[str]:
    lines, cur = [], ""
    for word in text.split():
        if cur and len(cur) + 1 + len(word) > width:
            lines.append(cur)
            cur = word
        else:
            cur = f"{cur} {word}".strip()
    return lines + ([cur] if cur else [])


def plan_sheet(
    plan: Polygon,
    walls: list[Wall],
    furniture: list[Furnishing],
    items: list[Item],
    room: str,
    captured: str,
    height: float,
    theta: float,
    credits: str,
    north_deg: float | None = None,
) -> Sheet:
    minx, miny, maxx, maxy = plan.bounds
    margin = 1.4  # metres around the plan for dimensions
    x0, y0, x1, y1 = AREA
    usable_w, usable_h = x1 - x0, y1 - y0 - 55  # leave room for the legend below the plan
    scale = next(
        (
            s
            for s in (25, 50, 100, 200)
            if (maxx - minx + 2 * margin) * 1000 / s <= usable_w and (maxy - miny + 2 * margin) * 1000 / s <= usable_h
        ),
        200,
    )
    k = 1000 / scale  # paper mm per metre
    ox = x0 + (usable_w - (maxx - minx) * k) / 2
    oy = y0 + (usable_h - (maxy - miny) * k) / 2

    def P(x: float, y: float) -> tuple[float, float]:
        return ox + (x - minx) * k, oy + (maxy - y) * k

    body: list[str] = [f'<rect x="{x0}" y="{y0}" width="{x1 - x0}" height="{y1 - y0}" fill="none"/>']
    # floor tone, then walls
    body.append(_poly([P(x, y) for x, y in list(plan.exterior.coords)[:-1]], fill="#f6f7f9", stroke="none"))
    for w in walls:
        a, b = np.array(w.a), np.array(w.b)
        u = (b - a) / max(w.length, 1e-9)
        out = np.array([u[1], -u[0]])  # the room is on the left, so the wall's outside is on the right
        cuts = [(0.0, w.length)]
        for o in w.openings:
            cuts = [
                piece
                for s, e in cuts
                for piece in ((s, min(e, o["offset"])), (max(s, o["offset"] + o["width"]), e))
                if piece[1] - piece[0] > 1e-3
            ]
        for s, e in cuts:
            s_ext = s - (WALL_T if s <= 1e-6 else 0)
            e_ext = e + (WALL_T if e >= w.length - 1e-6 else 0)
            quad = [a + u * s_ext, a + u * e_ext, a + u * e_ext + out * WALL_T, a + u * s_ext + out * WALL_T]
            if w.scanned:
                body.append(_poly([P(*q) for q in quad], fill=INK, stroke=INK, width=0.2))
            else:
                body.append(_poly([P(*q) for q in quad], stroke=MUTED, width=0.25, dash="1.2,0.8"))
        for o in w.openings:  # door: leaf and quarter swing into the room
            hinge = a + u * o["offset"]
            inward = np.array([-u[1], u[0]])
            tip = hinge + inward * o["width"]
            body.append(_line(P(*hinge), P(*tip), width=0.3))
            r = o["width"] * k
            end = P(*(hinge + u * o["width"]))
            body.append(
                f'<path d="M {P(*tip)[0]:.2f} {P(*tip)[1]:.2f} A {r:.2f} {r:.2f} 0 0 {1 if theta >= 0 else 0} '
                f'{end[0]:.2f} {end[1]:.2f}" fill="none" stroke="{MUTED}" stroke-width="0.18"/>'
            )
        # dimension string outside the wall: extension lines, a line with slashes, the length in metres
        off = WALL_T + 0.55
        da, db = a + out * off, b + out * off
        body += [
            _line(P(*(a + out * (WALL_T + 0.1))), P(*(da + out * 0.1)), MUTED, 0.13),
            _line(P(*(b + out * (WALL_T + 0.1))), P(*(db + out * 0.1)), MUTED, 0.13),
            _line(P(*da), P(*db), INK, 0.18),
        ]
        for end in (da, db):
            ex, ey = P(*end)
            body.append(_line((ex - 1, ey + 1), (ex + 1, ey - 1), INK, 0.3))
        mid = P(*((da + db) / 2 + out * 0.12))
        angle = -math.degrees(math.atan2(u[1], u[0]))
        if angle > 90 or angle <= -90:
            angle += 180
        body.append(_t(mid[0], mid[1], f"{w.length:.2f}", 2.6, rotate=angle))
    # overall dimensions
    left, top = P(minx, maxy)
    right, bottom = P(maxx, miny)
    over = (WALL_T + 1.15) * k
    body += [
        _line((left, bottom + over), (right, bottom + over), INK, 0.18),
        _t((left + right) / 2, bottom + over - 1.2, f"{maxx - minx:.2f}", 2.8, weight="bold"),
        _line((right + over, top), (right + over, bottom), INK, 0.18),
        _t(right + over - 1.2, (top + bottom) / 2, f"{maxy - miny:.2f}", 2.8, weight="bold", rotate=-90),
    ]
    # furniture outlines and labels
    for f in furniture:
        q = [P(f.lo[0], f.lo[1]), P(f.hi[0], f.lo[1]), P(f.hi[0], f.hi[1]), P(f.lo[0], f.hi[1])]
        body.append(_poly(q, fill="#ffffff", stroke=MUTED, width=0.22))
        cx, cy = P((f.lo[0] + f.hi[0]) / 2, (f.lo[1] + f.hi[1]) / 2)
        body.append(_t(cx, cy + 0.9, f.label, 2.2, fill=MUTED))
    # things: numbered dots
    for it in items:
        cx, cy = P(it.at[0], it.at[1])
        body.append(f'<circle cx="{cx:.2f}" cy="{cy:.2f}" r="2" fill="{CTA}"/>')
        body.append(_t(cx, cy + 0.9, str(it.number), 2.3, weight="bold", fill="#ffffff"))
    # scale bar and scan north
    sx, sy = x0 + 4, y1 - 46
    for i in range(4):
        body.append(
            f'<rect x="{sx + i * 0.5 * k:.2f}" y="{sy:.2f}" width="{0.5 * k:.2f}" height="1.6" '
            f'fill="{INK if i % 2 == 0 else "#ffffff"}" stroke="{INK}" stroke-width="0.15"/>'
        )
    body += [
        _t(sx, sy + 5, "0", 2.2, "start"),
        _t(sx + 2 * k, sy + 5, "2 m", 2.2, "end"),
        _t(sx, sy - 2, f"Scale 1:{scale} (on A3)", 2.4, "start", "bold"),
    ]
    # magnetic north when the scan had a reliable compass, else the scan's own +y; both turned into the plan frame
    home_dir = math.radians(north_deg) if north_deg is not None else 0.0
    d = np.array([math.sin(home_dir), math.cos(home_dir)])
    c, s_ = math.cos(-theta), math.sin(-theta)
    north = np.array([c * d[0] - s_ * d[1], s_ * d[0] + c * d[1]])
    nx, ny = x1 - 14, y1 - 52
    tip = (nx + north[0] * 7, ny - north[1] * 7)
    body += [
        _line((nx, ny), tip, INK, 0.4),
        f'<circle cx="{nx}" cy="{ny}" r="8" fill="none" stroke="{INK}" stroke-width="0.2"/>',
        _t(tip[0] + north[0] * 3, tip[1] - north[1] * 3 + 1, "N", 2.6, weight="bold"),
        _t(nx, ny + 12, "magnetic north" if north_deg is not None else "scan north", 2, fill=MUTED),
    ]
    # legend of things
    ly = y1 - 38
    body.append(_t(x0 + 60, ly, "Things", 3, "start", "bold"))
    # three columns that end before the title block; past 7 rows each, the lines get tighter, never wider
    cols = 3
    col_w = (x1 - (x0 + 60)) / cols
    rows = max(7, -(-len(items) // cols))
    step = min(4.4, 33 / rows)
    size = min(2.4, step * 0.55)
    for i, it in enumerate(items):
        col, row = divmod(i, rows)
        line = f"{it.number}  {it.title}, {it.place}"
        body.append(_t(x0 + 60 + col * col_w, ly + 5 + row * step, line, size, "start"))

    area, perimeter = plan.area, plan.length
    scanned = sum(w.length for w in walls if w.scanned)
    notes = [
        f"Floor {area:.1f} m², perimeter {perimeter:.1f} m, height {height:.2f} m.",
        f"Walls drawn dashed were not seen by the scan ({perimeter - scanned:.1f} m of {perimeter:.1f} m).",
        "Squared to the room's main direction; edges under 50 cm smoothed away. Dimensions in metres, to the inside "
        "face of the walls; about ±5 cm.",
        credits,
    ]
    summary = (
        f"Floor plan of the {room}: {maxx - minx:.2f} by {maxy - miny:.2f} metres, {area:.1f} square metres, "
        f"{len(furniture)} pieces of furniture and {len(items)} things marked."
    )
    return Sheet("A1.1", "Floor plan", _sheet("A1.1", "Floor plan", room, captured, body, summary, notes), summary)


def elevation_raster(
    points: np.ndarray, colors: np.ndarray, wall: Wall, height: float, px: float = 0.01, depth: float = 0.6
) -> np.ndarray:
    """The wall seen square on, from inside the room: points up to `depth` in front of it, nearest to the wall wins,
    small holes filled from their neighbours. (H, W, 3) uint8, white where the scan saw nothing."""
    a, b = np.array(wall.a), np.array(wall.b)
    u = (b - a) / max(wall.length, 1e-9)
    inward = np.array([-u[1], u[0]])
    rel = points[:, :2] - a
    s, d, z = rel @ u, rel @ inward, points[:, 2]
    keep = (s >= 0) & (s < wall.length) & (d >= -0.1) & (d <= depth) & (z >= 0) & (z < height)
    s, d, z, c = s[keep], d[keep], z[keep], colors[keep]
    w, h = max(1, int(wall.length / px)), max(1, int(height / px))
    img = np.zeros((h, w, 3), dtype=np.float32)
    mask = np.zeros((h, w), dtype=bool)
    order = np.argsort(-d)  # far first, so the nearest to the wall is written last
    cols = np.clip((s[order] / px).astype(int), 0, w - 1)
    rows = np.clip(((height - z[order]) / px).astype(int), 0, h - 1)
    img[rows, cols] = c[order]
    mask[rows, cols] = True
    for _ in range(4):  # fill pinholes between points from their neighbours
        weight = ndimage.uniform_filter(mask.astype(np.float32), 3)
        filled = np.stack([ndimage.uniform_filter(img[..., i] * mask, 3) for i in range(3)], -1)
        grow = ~mask & (weight > 0.3)
        img[grow] = filled[grow] / weight[grow, None]
        mask |= grow
    img[~mask] = 255
    return img.clip(0, 255).astype(np.uint8)


def elevations_sheet(
    walls: list[Wall],
    images_png_b64: list[str],
    furniture: list[Furnishing],
    room: str,
    captured: str,
    height: float,
    credits: str,
) -> Sheet:
    """Up to four scanned walls in a 2 × 2 grid, each with its photo elevation, levels and width."""
    x0, y0, x1, y1 = AREA
    cell_w, cell_h = (x1 - x0) / 2, (y1 - y0) / 2
    body: list[str] = []
    for i, (w, img) in enumerate(zip(walls, images_png_b64, strict=False)):
        cx, cy = x0 + (i % 2) * cell_w, y0 + (i // 2) * cell_h
        k = min((cell_w - 26) / w.length, (cell_h - 24) / height)  # mm per metre
        iw, ih = w.length * k, height * k
        ix, iy = cx + 16, cy + 6
        body.append(
            f'<image x="{ix:.2f}" y="{iy:.2f}" width="{iw:.2f}" height="{ih:.2f}" preserveAspectRatio="none" '
            f'href="data:image/png;base64,{img}"/>'
        )
        body.append(
            f'<rect x="{ix:.2f}" y="{iy:.2f}" width="{iw:.2f}" height="{ih:.2f}" fill="none" '
            f'stroke="{INK}" stroke-width="0.3"/>'
        )
        a, b = np.array(w.a), np.array(w.b)
        u = (b - a) / max(w.length, 1e-9)
        inward = np.array([-u[1], u[0]])
        for f in furniture:  # pieces standing in front of this wall, as dashed outlines
            corners = np.array([[f.lo[0], f.lo[1]], [f.hi[0], f.lo[1]], [f.hi[0], f.hi[1]], [f.lo[0], f.hi[1]]]) - a
            s, d = corners @ u, corners @ inward
            if d.min() > 1.2 or d.max() < -0.1 or s.max() < 0 or s.min() > w.length:
                continue
            s0, s1 = max(s.min(), 0), min(s.max(), w.length)
            body.append(
                f'<rect x="{ix + s0 * k:.2f}" y="{iy + (height - f.hi[2]) * k:.2f}" width="{(s1 - s0) * k:.2f}" '
                f'height="{(f.hi[2] - f.lo[2]) * k:.2f}" fill="none" stroke="{BLUE}" stroke-width="0.25" '
                f'stroke-dasharray="1,0.7"/>'
            )
        for level, name in ((0.0, "floor 0.00"), (0.75, "0.75"), (height, f"ceiling {height:.2f}")):
            ly = iy + (height - level) * k
            body += [_line((ix - 3, ly), (ix, ly), INK, 0.2), _t(ix - 3.5, ly + 0.9, name, 2, "end")]
        body += [
            _line((ix, iy + ih + 4), (ix + iw, iy + ih + 4), INK, 0.18),
            _t(ix + iw / 2, iy + ih + 3, f"{w.length:.2f}", 2.6),
            _t(ix, iy + ih + 10, f"Elevation {i + 1}", 3, "start", "bold"),
        ]
    summary = (
        f"Interior elevations of the {room}: {len(images_png_b64)} walls seen square on from the scan's own "
        "coloured points, with floor, desk height and ceiling levels."
    )
    notes = [
        "Each wall as the scan saw it from inside the room: the nearest measured point to the wall wins; white is "
        "where the scan saw nothing. Furniture in front of a wall is dashed.",
        credits,
    ]
    return Sheet(
        "A2.1",
        "Interior elevations",
        _sheet("A2.1", "Interior elevations", room, captured, body, summary, notes),
        summary,
    )
