import { useEffect, useState } from "react";
import { useSearchParams, Link } from "react-router-dom";
import { useApi } from "../lib/useApi";
import RAGBadge from "../components/RAGBadge";
import type { RagStatus } from "../lib/rag";

interface SearchResults {
  projects: { project_id: number; project_name: string; customer_name: string | null }[];
  reports: {
    id: number;
    project_id: number;
    project_name: string;
    submission_at: string;
    rag_status: RagStatus | null;
    narrative_summary: string | null;
  }[];
  blockers: {
    id: number;
    report_id: number;
    project_name: string;
    description: string;
    severity: string | null;
  }[];
}

export default function SearchView() {
  const [params] = useSearchParams();
  const api = useApi();
  const [results, setResults] = useState<SearchResults | null>(null);
  const q = params.get("q") ?? "";

  useEffect(() => {
    if (!q) return;
    api.get<SearchResults>("/api/search", { params: { q } }).then((r) => setResults(r.data));
  }, [api, q]);

  if (!q) return <p className="text-slate-500">Enter a search term.</p>;
  if (!results) return <p className="text-slate-500">Searching…</p>;

  return (
    <div className="space-y-6">
      <h2 className="text-2xl font-semibold tracking-tight">Results for "{q}"</h2>

      <Section title={`Projects (${results.projects.length})`}>
        <ul className="divide-y divide-slate-200">
          {results.projects.map((p) => (
            <li key={p.project_id} className="py-2">
              <Link to={`/projects/${p.project_id}`} className="font-medium hover:underline">
                {p.project_name}
              </Link>
              {p.customer_name && <span className="text-slate-500 text-sm ml-2">({p.customer_name})</span>}
            </li>
          ))}
          {!results.projects.length && <li className="py-2 text-slate-500 text-sm">No projects match.</li>}
        </ul>
      </Section>

      <Section title={`Reports (${results.reports.length})`}>
        <ul className="divide-y divide-slate-200">
          {results.reports.map((r) => (
            <li key={r.id} className="py-2 flex items-start gap-3">
              <RAGBadge status={r.rag_status} />
              <div className="flex-1">
                <Link to={`/projects/${r.project_id}`} className="font-medium hover:underline">
                  {r.project_name}
                </Link>
                <div className="text-xs text-slate-500">
                  {new Date(r.submission_at).toLocaleDateString()}
                </div>
                {r.narrative_summary && (
                  <p className="text-sm text-slate-700 mt-1">{r.narrative_summary}</p>
                )}
              </div>
            </li>
          ))}
          {!results.reports.length && <li className="py-2 text-slate-500 text-sm">No reports match.</li>}
        </ul>
      </Section>

      <Section title={`Blockers (${results.blockers.length})`}>
        <ul className="divide-y divide-slate-200">
          {results.blockers.map((b) => (
            <li key={b.id} className="py-2">
              <div className="text-xs uppercase tracking-wide text-slate-500">
                {b.severity ?? "INFO"} · {b.project_name}
              </div>
              <div className="text-sm">{b.description}</div>
            </li>
          ))}
          {!results.blockers.length && <li className="py-2 text-slate-500 text-sm">No blockers match.</li>}
        </ul>
      </Section>
    </div>
  );
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="rounded-lg border border-slate-200 bg-white p-4">
      <h3 className="font-semibold mb-2">{title}</h3>
      {children}
    </div>
  );
}
