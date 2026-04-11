interface Props {
  budget: number | null | undefined;
  consumed: number | null | undefined;
}

export default function HoursGauge({ budget, consumed }: Props) {
  if (budget == null || consumed == null || budget <= 0) {
    return <div className="text-slate-400 text-sm">No hours data</div>;
  }
  const pct = Math.min(100, (consumed / budget) * 100);
  const over = consumed > budget;
  const bar = over ? "bg-red-500" : pct > 85 ? "bg-amber-500" : "bg-emerald-500";
  return (
    <div className="space-y-1">
      <div className="flex justify-between text-xs text-slate-600">
        <span>{consumed.toFixed(1)} / {budget.toFixed(1)} hrs</span>
        <span className={over ? "text-red-600 font-semibold" : ""}>{pct.toFixed(0)}%</span>
      </div>
      <div className="h-2 rounded bg-slate-200 overflow-hidden">
        <div className={`h-full ${bar} transition-all`} style={{ width: `${pct}%` }} />
      </div>
    </div>
  );
}
