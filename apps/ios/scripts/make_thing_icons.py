"""Draws Recall's thing icons (our own artwork, Apache-2.0) as SVGs in the app's asset catalog.

Each icon is two layers on a 64 x 64 grid:
  thing-<kind>-fill  the body, drawn black; the app tints it with the thing's measured colour (template image)
  thing-<kind>-line  the outline and details in fixed colours (ink #1c1e21, pale #dfe3ee), drawn over the fill

Run:  python3 apps/ios/scripts/make_thing_icons.py
"""

from __future__ import annotations

import json
from pathlib import Path

INK, PALE = "#1c1e21", "#dfe3ee"
OUT = Path(__file__).resolve().parents[1] / "Recall/Resources/Assets.xcassets/Things"

# body: shapes that take the colour (and get an ink outline); line: details over them (ink unless they say otherwise)
ICONS: dict[str, dict[str, list[str]]] = {
    "keys": {
        "body": ['<circle cx="20" cy="26" r="12"/>', '<rect x="29" y="22" width="27" height="8" rx="2"/>',
                 '<rect x="44" y="28" width="5" height="9" rx="1.5"/>', '<rect x="51" y="28" width="5" height="12" rx="1.5"/>'],
        "line": [f'<circle cx="18" cy="26" r="4.5" fill="#fff" stroke="{INK}" stroke-width="3"/>'],
    },
    "wallet": {
        "body": ['<rect x="7" y="15" width="50" height="36" rx="7"/>'],
        "line": [f'<rect x="33" y="26" width="24" height="14" rx="5" fill="{PALE}" stroke="{INK}" stroke-width="3"/>',
                 f'<circle cx="43" cy="33" r="2.5" fill="{INK}"/>', f'<path d="M12 21h22" stroke="{INK}" stroke-width="3" stroke-linecap="round"/>'],
    },
    "handbag": {
        "body": ['<path d="M11 27h42l-4 27a3 3 0 0 1-3 2.5H18a3 3 0 0 1-3-2.5z"/>'],
        "line": [f'<path d="M22 27c0-10 4-15 10-15s10 5 10 15" fill="none" stroke="{INK}" stroke-width="3.5" stroke-linecap="round"/>',
                 f'<rect x="28" y="33" width="8" height="6" rx="2" fill="{PALE}" stroke="{INK}" stroke-width="2.5"/>'],
    },
    "backpack": {
        "body": ['<rect x="13" y="15" width="38" height="44" rx="11"/>'],
        "line": [f'<path d="M25 15c0-6 3-8 7-8s7 2 7 8" fill="none" stroke="{INK}" stroke-width="3.5" stroke-linecap="round"/>',
                 f'<rect x="20" y="37" width="24" height="15" rx="5" fill="{PALE}" stroke="{INK}" stroke-width="3"/>',
                 f'<path d="M26 43h12" stroke="{INK}" stroke-width="3" stroke-linecap="round"/>'],
    },
    "book": {
        "body": ['<rect x="13" y="8" width="38" height="46" rx="4"/>'],
        "line": [f'<rect x="17" y="49" width="34" height="8" rx="2" fill="#fff" stroke="{INK}" stroke-width="3"/>',
                 f'<path d="M20 8v41" stroke="{INK}" stroke-width="3"/>',
                 f'<path d="M27 20h17M27 27h12" stroke="{PALE}" stroke-width="3" stroke-linecap="round"/>'],
    },
    "bottle": {
        "body": ['<path d="M25 16h14l5 9v29a4 4 0 0 1-4 4H24a4 4 0 0 1-4-4V25z"/>'],
        "line": [f'<rect x="26" y="5" width="12" height="10" rx="3" fill="{PALE}" stroke="{INK}" stroke-width="3"/>',
                 f'<rect x="20" y="32" width="24" height="12" fill="#fff" fill-opacity=".85" stroke="{INK}" stroke-width="3"/>'],
    },
    "glasses": {
        "body": ['<circle cx="19" cy="34" r="12"/>', '<circle cx="45" cy="34" r="12"/>'],
        "line": [f'<circle cx="19" cy="34" r="7" fill="{PALE}" stroke="{INK}" stroke-width="2.5"/>',
                 f'<circle cx="45" cy="34" r="7" fill="{PALE}" stroke="{INK}" stroke-width="2.5"/>',
                 f'<path d="M28 31c2-3 6-3 8 0" fill="none" stroke="{INK}" stroke-width="3" stroke-linecap="round"/>',
                 f'<path d="M7 30 3 22M57 30l4-8" stroke="{INK}" stroke-width="3" stroke-linecap="round"/>'],
    },
    "phone": {
        "body": ['<rect x="17" y="5" width="30" height="54" rx="7"/>'],
        "line": [f'<rect x="21" y="11" width="22" height="40" rx="3" fill="{PALE}" stroke="{INK}" stroke-width="2.5"/>',
                 f'<path d="M29 55h6" stroke="{INK}" stroke-width="3" stroke-linecap="round"/>'],
    },
    "remote": {
        "body": ['<rect x="21" y="5" width="22" height="54" rx="9"/>'],
        "line": [f'<circle cx="32" cy="18" r="6" fill="{PALE}" stroke="{INK}" stroke-width="2.5"/>',
                 f'<circle cx="27" cy="32" r="2.5" fill="{INK}"/>', f'<circle cx="37" cy="32" r="2.5" fill="{INK}"/>',
                 f'<circle cx="27" cy="41" r="2.5" fill="{INK}"/>', f'<circle cx="37" cy="41" r="2.5" fill="{INK}"/>'],
    },
    "mug": {
        "body": ['<rect x="10" y="18" width="34" height="38" rx="6"/>'],
        "line": [f'<path d="M44 26c8 0 12 4 12 10s-4 10-12 10" fill="none" stroke="{INK}" stroke-width="4" stroke-linecap="round"/>',
                 f'<path d="M21 6c-3 4 3 6 0 10M32 6c-3 4 3 6 0 10" fill="none" stroke="{INK}" stroke-width="2.5" stroke-linecap="round"/>'],
    },
    "laptop": {
        "body": ['<rect x="11" y="11" width="42" height="31" rx="4"/>', '<path d="M5 45h54l-4 9H9z"/>'],
        "line": [f'<rect x="15" y="15" width="34" height="23" rx="2" fill="{PALE}" stroke="{INK}" stroke-width="2.5"/>',
                 f'<path d="M27 49h10" stroke="{INK}" stroke-width="2.5" stroke-linecap="round"/>'],
    },
    "headphones": {
        "body": ['<rect x="7" y="33" width="14" height="21" rx="6"/>', '<rect x="43" y="33" width="14" height="21" rx="6"/>'],
        "line": [f'<path d="M12 38V32c0-12 9-21 20-21s20 9 20 21v6" fill="none" stroke="{INK}" stroke-width="4" stroke-linecap="round"/>'],
    },
    "charger": {
        "body": ['<rect x="18" y="20" width="28" height="26" rx="6"/>'],
        "line": [f'<rect x="23" y="7" width="5" height="13" rx="1.5" fill="{PALE}" stroke="{INK}" stroke-width="2.5"/>',
                 f'<rect x="36" y="7" width="5" height="13" rx="1.5" fill="{PALE}" stroke="{INK}" stroke-width="2.5"/>',
                 f'<path d="M32 46v5c0 6 8 6 8 11" fill="none" stroke="{INK}" stroke-width="3.5" stroke-linecap="round"/>',
                 f'<path d="m33 26-5 8h7l-4 7" fill="none" stroke="{INK}" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/>'],
    },
    "watch": {
        "body": ['<rect x="23" y="3" width="18" height="58" rx="6"/>', '<rect x="14" y="17" width="36" height="30" rx="10"/>'],
        "line": [f'<rect x="19" y="22" width="26" height="20" rx="6" fill="{PALE}" stroke="{INK}" stroke-width="2.5"/>',
                 f'<path d="M32 26v7l4 3" fill="none" stroke="{INK}" stroke-width="2.5" stroke-linecap="round"/>'],
    },
    "passport": {
        "body": ['<rect x="13" y="6" width="38" height="52" rx="5"/>'],
        "line": [f'<circle cx="32" cy="27" r="9" fill="{PALE}" stroke="{INK}" stroke-width="2.5"/>',
                 f'<path d="M23 27h18M32 18c-4 5-4 13 0 18 4-5 4-13 0-18" fill="none" stroke="{INK}" stroke-width="2"/>',
                 f'<path d="M23 45h18" stroke="{PALE}" stroke-width="3" stroke-linecap="round"/>'],
    },
    "unknown": {  # the box: Recall isn't sure what this is
        "body": ['<path d="M32 7 55 18v28L32 57 9 46V18z"/>'],
        "line": [f'<path d="M9 18 32 29 55 18M32 29v28" fill="none" stroke="{INK}" stroke-width="3" stroke-linejoin="round"/>',
                 f'<path d="M20 12.5 43 24" stroke="{PALE}" stroke-width="3"/>'],
    },
}


def svg(parts: list[str]) -> str:
    return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="64" height="64">' + "".join(parts) + "</svg>\n"


def outline(shape: str) -> str:
    return shape.replace("/>", f' fill="none" stroke="{INK}" stroke-width="3" stroke-linejoin="round"/>')


def imageset(name: str, body: str, template: bool) -> None:
    folder = OUT / f"{name}.imageset"
    folder.mkdir(parents=True, exist_ok=True)
    (folder / f"{name}.svg").write_text(body)
    props = {"preserves-vector-representation": True, "template-rendering-intent": "template" if template else "original"}
    contents = {"images": [{"filename": f"{name}.svg", "idiom": "universal"}], "info": {"author": "xcode", "version": 1},
                "properties": props}
    (folder / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
    for kind, icon in ICONS.items():
        imageset(f"thing-{kind}-fill", svg([s.replace("/>", ' fill="#000"/>') for s in icon["body"]]), template=True)
        imageset(f"thing-{kind}-line", svg([outline(s) for s in icon["body"]] + icon["line"]), template=False)
    print(f"{len(ICONS)} icons -> {OUT}")


if __name__ == "__main__":
    main()
