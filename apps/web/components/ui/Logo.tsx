/** Recall's own mark: the Braille cell for "R" (dots 1, 2, 3, 5) in a rounded tile. */
export function Logo({ className = "" }: { className?: string }) {
  const on = new Set([1, 2, 3, 5]);
  return (
    <span className={`inline-flex items-center gap-2 ${className}`}>
      <svg viewBox="0 0 32 32" className="size-8" aria-hidden="true">
        <rect width="32" height="32" rx="8" fill="white" />
        {[1, 2, 3, 4, 5, 6].map((d) => {
          const cx = d <= 3 ? 12 : 20;
          const cy = 8 + ((d - 1) % 3) * 8;
          return <circle key={d} cx={cx} cy={cy} r="3" fill={on.has(d) ? "#3b5998" : "#dfe3ee"} />;
        })}
      </svg>
      <span className="text-xl font-extrabold tracking-[0.12em]">RECALL</span>
    </span>
  );
}
