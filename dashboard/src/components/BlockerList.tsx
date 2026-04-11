import { AlertTriangle } from "lucide-react";

export interface Blocker {
  id: number;
  description: string;
  severity: "HIGH" | "MEDIUM" | "LOW" | null;
  is_resolved: boolean;
}

const sevStyle: Record<string, string> = {
  HIGH:   "bg-red-50 border-red-400 text-red-700",
  MEDIUM: "bg-amber-50 border-amber-400 text-amber-700",
  LOW:    "bg-slate-50 border-slate-300 text-slate-600",
};

export default function BlockerList({ items }: { items: Blocker[] }) {
  if (!items?.length) return <p className="text-slate-500 text-sm">No blockers extracted.</p>;
  return (
    <ul className="space-y-2">
      {items.map((b) => {
        const style = b.severity ? sevStyle[b.severity] : sevStyle.LOW;
        return (
          <li key={b.id} className={`border-l-4 px-3 py-2 rounded ${style}`}>
            <div className="flex items-center gap-2">
              <AlertTriangle className="w-4 h-4" />
              <span className="text-xs uppercase tracking-wide">{b.severity ?? "INFO"}</span>
              {b.is_resolved && <span className="text-xs text-emerald-700">(resolved)</span>}
            </div>
            <div className="mt-1 text-sm">{b.description}</div>
          </li>
        );
      })}
    </ul>
  );
}
