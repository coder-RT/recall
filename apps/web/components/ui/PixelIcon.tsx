import { PIXEL_GRID, pixelRects, type PixelIconName } from "@/lib/pixel-icons";

/** A pixel icon from lib/pixel-icons.ts as inline SVG. Decorative. */
export function PixelIcon({ name, size = 24, className = "" }: { name: PixelIconName; size?: number; className?: string }) {
  return (
    <svg
      viewBox={`0 0 ${PIXEL_GRID} ${PIXEL_GRID}`}
      width={size}
      height={size}
      // crisp cells once there is at least a screen pixel per cell; smoothed when smaller
      shapeRendering={size >= PIXEL_GRID ? "crispEdges" : "auto"}
      aria-hidden="true"
      className={className}
    >
      {pixelRects(name).map((r) => (
        <rect key={`${r.x}-${r.y}`} x={r.x} y={r.y - 0.02} width={r.w} height={1.04} fill={r.fill} />
      ))}
    </svg>
  );
}
