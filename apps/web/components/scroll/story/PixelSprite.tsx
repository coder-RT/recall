import { gridRects } from "@/lib/pixel-icons";

/**
 * A pixel sprite with several frames, each a <g data-frame="name">. Only `visible` is shown in the
 * markup; GSAP flips frames by toggling their opacity. One cell = one SVG unit.
 */
export function PixelSprite<F extends string>({
  frames,
  palette,
  visible,
}: {
  frames: Record<F, readonly string[]>;
  palette: Record<string, string>;
  visible: F;
}) {
  return (
    <g shapeRendering="crispEdges">
      {(Object.keys(frames) as F[]).map((name) => (
        <g key={name} data-frame={name} opacity={name === visible ? 1 : 0}>
          {gridRects(frames[name], palette).map((r) => (
            <rect key={`${r.x}-${r.y}`} x={r.x - 0.05} y={r.y - 0.05} width={1.1} height={1.1} fill={r.fill} />
          ))}
        </g>
      ))}
    </g>
  );
}
