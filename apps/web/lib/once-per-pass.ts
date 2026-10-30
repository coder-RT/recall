/**
 * A moment that fires once per pass through a section: `fire` runs only while armed and outside
 * the cooldown, then disarms; the section calls `rearm` once the visitor has gone back through it.
 * The cooldown stops quick back-and-forth scrolling at the end from repeating it.
 */
export function oncePerPass({ cooldown = 8000 } = {}) {
  let armed = true;
  let last = -Infinity;
  return {
    fire(fn: () => void) {
      if (!armed || performance.now() - last < cooldown) return;
      armed = false;
      last = performance.now();
      fn();
    },
    rearm() {
      armed = true;
    },
  };
}
