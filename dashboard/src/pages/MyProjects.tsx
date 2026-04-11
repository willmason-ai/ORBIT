import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { useApi } from "../lib/useApi";
import RAGBadge from "../components/RAGBadge";
import HoursGauge from "../components/HoursGauge";
import type { RagStatus } from "../lib/rag";

interface ProjectRow {
  project_id: number;
  project_name: string;
  customer_name: string | null;
  rag_status: RagStatus | null;
  total_hours_budget: number | null;
  hours_consumed: number | null;
  last_updated: string | null;
}

export default function MyProjects() {
  const api = useApi();
  const [rows, setRows] = useState<ProjectRow[]>([]);

  useEffect(() => {
    api.get<ProjectRow[]>("/api/dashboard/me").then((r) => setRows(r.data));
  }, [api]);

  return (
    <div className="space-y-4">
      <h2 className="text-2xl font-semibold tracking-tight">My Projects</h2>
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        {rows.map((p) => (
          <Link
            key={p.project_id}
            to={`/projects/${p.project_id}`}
            className="block rounded-lg border border-slate-200 bg-white p-4 hover:shadow-md transition"
          >
            <div className="flex items-start justify-between">
              <div>
                <div className="font-semibold">{p.project_name}</div>
                {p.customer_name && <div className="text-xs text-slate-500">{p.customer_name}</div>}
              </div>
              <RAGBadge status={p.rag_status} />
            </div>
            <div className="mt-3">
              <HoursGauge budget={p.total_hours_budget} consumed={p.hours_consumed} />
            </div>
          </Link>
        ))}
        {!rows.length && (
          <p className="text-slate-500 text-sm">
            No submissions yet — email your PPTX to <code>orbit@presidiorocks.com</code>.
          </p>
        )}
      </div>
    </div>
  );
}
