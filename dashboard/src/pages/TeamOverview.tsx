import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { useApi } from "../lib/useApi";

interface TeamRow {
  employee_id: number;
  employee_name: string;
  employee_email: string;
  green_count: number;
  amber_count: number;
  red_count: number;
  total_active_projects: number;
}

export default function TeamOverview() {
  const api = useApi();
  const [rows, setRows] = useState<TeamRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    api.get<TeamRow[]>("/api/dashboard/team")
      .then((res) => setRows(res.data))
      .catch((e) => setError(e.message))
      .finally(() => setLoading(false));
  }, [api]);

  if (loading) return <p className="text-slate-500">Loading team…</p>;
  if (error)   return <p className="text-red-600">Error: {error}</p>;
  if (!rows.length) {
    return (
      <div className="text-slate-500">
        No reports yet. Ask engineers to email their PPTX to <code>orbit@presidiorocks.com</code>.
      </div>
    );
  }

  return (
    <div className="space-y-4">
      <h2 className="text-2xl font-semibold tracking-tight">Team Overview</h2>
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        {rows.map((r) => (
          <Link
            key={r.employee_id}
            to={`/employees/${r.employee_id}`}
            className="block rounded-lg border border-slate-200 bg-white p-4 hover:shadow-md transition"
          >
            <div className="flex items-center gap-3">
              <div className="w-10 h-10 rounded-full bg-slate-200 text-slate-600 flex items-center justify-center font-semibold">
                {initials(r.employee_name)}
              </div>
              <div>
                <div className="font-semibold">{r.employee_name}</div>
                <div className="text-xs text-slate-500">{r.employee_email}</div>
              </div>
            </div>
            <div className="mt-4 flex items-center gap-3 text-sm">
              <span className="text-green-700">🟢 {r.green_count}</span>
              <span className="text-amber-700">🟡 {r.amber_count}</span>
              <span className="text-red-700">🔴 {r.red_count}</span>
              <span className="ml-auto text-slate-500">{r.total_active_projects} active</span>
            </div>
          </Link>
        ))}
      </div>
    </div>
  );
}

function initials(name: string): string {
  return name
    .split(" ")
    .map((p) => p[0])
    .filter(Boolean)
    .slice(0, 2)
    .join("")
    .toUpperCase();
}
