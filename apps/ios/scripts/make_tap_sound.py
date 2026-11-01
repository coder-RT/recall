"""Makes Recall's tab tap sound (Recall/Resources/tap.wav): a soft, short "tock", made here from two damped sine
waves, so it is our own sound with nothing to licence. Run: python3 scripts/make_tap_sound.py"""

import math
import struct
import wave
from pathlib import Path

RATE = 44_100
LENGTH_S = 0.045
OUT = Path(__file__).resolve().parent.parent / "Recall" / "Resources" / "tap.wav"


def sample(t: float) -> float:
    # a low body and a quieter higher click, both dying away fast; a 2 ms fade-in avoids a pop
    body = math.sin(2 * math.pi * 520 * t) * math.exp(-t * 110)
    click = 0.35 * math.sin(2 * math.pi * 1650 * t) * math.exp(-t * 260)
    return min(1.0, t / 0.002) * (body + click)


def main() -> None:
    n = int(RATE * LENGTH_S)
    peak = 0.45  # well below full scale: a tap, not a beep
    frames = b"".join(struct.pack("<h", int(32767 * peak * sample(i / RATE))) for i in range(n))
    with wave.open(str(OUT), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(frames)
    print(f"wrote {OUT} ({n} samples)")


if __name__ == "__main__":
    main()
