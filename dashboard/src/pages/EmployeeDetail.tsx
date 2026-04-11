import { useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { useApi } from "../lib/useApi";
import RAGBadge from "../components/RAGBadge";
import HoursGauge from "../components/HoursGauge";
import type { RagStatus } from "../lib/rag";

interface Employee {
  id: number;
  full_name: string;
  email: string;
  report_count: number;
}

interface ProjectRow {
  project_id: number;
  project_name: string;
  customer_name: string | null;
  rag_status: RagStatus | null;
  total_hours_budget: number | null;
  hours_consumed: number | null;
  last_updated: string | null;
  needs_review: boolean;
}

export default function EmployeeDetail() {
  const { id } = useParams<{ id: string }>();
  const api = useApi();
  const [emp, setEmp] = useState<Employee | null>(null);
  const [projects, setProjects] = useState<ProjectRow[]>([]);

  useEffect(() => {
    if (!id) return;
    Promise.all([
      api.get<Employee>(`/api/employees/${id}`),
      api.get<ProjectRow[]>(`/api/employees/${id}/projects`),
    ]).then(([e, p]) => {
      setEmp(e.data);
      setProjects(p.data);
    });
  }, [api, id]);

  if (!emp) return <p className="text-slate-500">Loading…</p>;

  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-2xl font-semibold tracking-tight">{emp.full_name}</h2>
        <p className="text-slate-500 text-sm">{emp.email} · {emp.report_count} reports</p>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        {projects.map((p) => (
          <Link
            key={p.project_id}
            to={`/projects/${p.project_id}`}
            className="block rounded-lg border border-slate-200 bg-white p-4 hover:shadow-md transition"
          >
            <div className="flex items-start justify-between gap-2">
              <div>
                <div className="font-semibold">{p.project_name}</div>
                {p.customer_name && (
                  <div className="text-xs text-slate-500">{p.customer_name}</div>
                )}
              </div>
              <RAGBadge status={p.rag_status} />
            </div>
            <div className="mt-3">
              <HoursGauge budget={p.total_hours_budget} consumed={p.hours_consumed} />
            </div>
            <div className="mt-2 text-xs text-slate-500">
              {p.last_updated ? `Updated ${new Date(p.last_updated).toLocaleDateString()}` : "Never"}
              {p.needs_review && <span className="ml-2 text-amber-700">⚠ Needs review</span>}
            </div>
          </Link>
        ))}
        {!projects.length && <p className="text-slate-500 text-sm">No active projects.</p>}
      </div>
    </div>
  );
}
