import { Check, Clock } from "lucide-react";

export interface Milestone {
  id: number;
  description: string;
  completed: boolean;
  due_date: string | null;
}

export default function MilestoneList({ items }: { items: Milestone[] }) {
  if (!items?.length) return <p className="text-slate-500 text-sm">No milestones extracted.</p>;
  return (
    <ul className="divide-y divide-slate-200">
      {items.map((m) => (
        <li key={m.id} className="py-2 flex items-start gap-3">
          {m.completed
            ? <Check className="w-4 h-4 text-emerald-600 mt-0.5" />
            : <Clock className="w-4 h-4 text-slate-400 mt-0.5" />}
          <div className="flex-1">
            <div className={m.completed ? "line-through text-slate-500" : ""}>{m.description}</div>
            {m.due_date && (
              <div className="text-xs text-slate-500">Due {m.due_date}</div>
            )}
          </div>
        </li>
      ))}
    </ul>
  );
}
