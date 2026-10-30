/** Measured numbers from the run, each beside a thin rule. Plain HTML, so it reads without JavaScript. */
export function ViewerStats({ label, items }: { label: string; items: { value: string; label: string }[] }) {
  return (
    <section aria-label={label}>
      <h2 className="text-sm font-semibold text-muted">{label}</h2>
      <dl className="mt-3 grid grid-cols-2 gap-x-6 gap-y-3 sm:grid-cols-4">
        {items.map((item) => (
          <div key={item.label} data-stat className="flex flex-col-reverse border-l-2 border-fb-blue pl-3">
            <dt className="text-sm text-muted">{item.label}</dt>
            <dd className="text-3xl font-light tabular-nums text-ink">{item.value}</dd>
          </div>
        ))}
      </dl>
    </section>
  );
}
