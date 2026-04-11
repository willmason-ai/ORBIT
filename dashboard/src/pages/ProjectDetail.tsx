import { useEffect, useMemo, useState } from "react";
import { useParams } from "react-router-dom";
import { Download, CheckCircle2 } from "lucide-react";
import { useApi } from "../lib/useApi";
import RAGBadge from "../components/RAGBadge";
import HoursGauge from "../components/HoursGauge";
import MilestoneList, { type Milestone } from "../components/MilestoneList";
import BlockerList, { type Blocker } from "../components/BlockerList";
import RAGTrendChart from "../components/RAGTrendChart";
import type { RagStatus } from "../lib/rag";

interface ProjectSummary {
  project_id: number;
  project_name: string;
  customer_name: string | null;
  owner_name: string | null;
  owner_email: string | null;
  rag_status: RagStatus | null;
  total_hours_budget: number | null;
  hours_consumed: number | null;
  last_updated: string | null;
  latest_report_id: number | null;
  needs_review: boolean;
}

interface ReportDetail {
  id: number;
  rag_status: RagStatus | null;
  rag_rationale: string | null;
  narrative_summary: string | null;
  parse_confidence: number | null;
  needs_review: boolean;
  milestones: Milestone[];
  blockers: Blocker[];
  notes: { id: number; note_text: string; created_at: string; supervisor_name: string | null }[];
}

interface HistoryRow {
  id: number;
  submission_at: string;
  pct_hours_consumed: number | null;
  rag_status: RagStatus | null;
}

type Tab = "milestones" | "blockers" | "history";

export default function ProjectDetail() {
  const { id } = useParams<{ id: string }>();
  const api = useApi();
  const [project, setProject] = useState<ProjectSummary | null>(null);
  const [report, setReport] = useState<ReportDetail | null>(null);
  const [history, setHistory] = useState<HistoryRow[]>([]);
  const [tab, setTab] = useState<Tab>("milestones");
  const [noteDraft, setNoteDraft] = useState("");

  const apiBase = useMemo(() => api.defaults.baseURL ?? "", [api]);

  useEffect(() => {
    if (!id) return;
    api.get<ProjectSummary>(`/api/projects/${id}`).then((res) => {
      setProject(res.data);
      if (res.data.latest_report_id) {
        api.get<ReportDetail>(`/api/reports/${res.data.latest_report_id}`).then((r) => setReport(r.data));
      }
    });
    api.get<HistoryRow[]>(`/api/projects/${id}/history`).then((r) => setHistory(r.data));
  }, [api, id]);

  async function confirmExtraction() {
    if (!report) return;
    await api.post(`/api/reports/${report.id}/confirm`);
    setReport({ ...report, needs_review: false });
  }

  async function addNote() {
    if (!report || !noteDraft.trim()) return;
    await api.post(`/api/reports/${report.id}/notes`, { note_text: noteDraft });
    setNoteDraft("");
    const r = await api.get<ReportDetail>(`/api/reports/${report.id}`);
    setReport(r.data);
  }

  if (!project) return <p className="text-slate-500">Loading…</p>;

  return (
    <div className="space-y-6">
      <div className="flex items-start justify-between gap-4">
        <div>
          <h2 className="text-2xl font-semibold tracking-tight">{project.project_name}</h2>
          <p className="text-slate-500 text-sm">
            {project.customer_name ?? "No customer"} · {project.owner_name} ({project.owner_email})
          </p>
        </div>
        <div className="flex items-center gap-3">
          <RAGBadge status={project.rag_status} />
          {report?.needs_review && (
            <button
              onClick={confirmExtraction}
              className="inline-flex items-center gap-1 text-sm px-3 py-1.5 rounded bg-amber-100 text-amber-800 hover:bg-amber-200"
            >
              <CheckCircle2 className="w-4 h-4" /> Confirm extraction
            </button>
          )}
          {project.latest_report_id && (
            <a
              href={`${apiBase}/api/reports/${project.latest_report_id}/pptx`}
              className="inline-flex items-center gap-1 text-sm px-3 py-1.5 rounded bg-slate-900 text-white hover:bg-slate-700"
            >
              <Download className="w-4 h-4" /> PPTX
            </a>
          )}
        </div>
      </div>

      <div className="rounded-lg border border-slate-200 bg-white p-4">
        <HoursGauge budget={project.total_hours_budget} consumed={project.hours_consumed} />
      </div>

      {report?.narrative_summary && (
        <div className="rounded-lg border border-slate-200 bg-white p-4">
          <div className="text-xs uppercase tracking-wide text-slate-500 mb-1">Narrative</div>
          <p className="text-sm">{report.narrative_summary}</p>
          {report.rag_rationale && (
            <p className="text-sm text-slate-600 mt-2 italic">Rationale: {report.rag_rationale}</p>
          )}
        </div>
      )}

      <div className="rounded-lg border border-slate-200 bg-white">
        <div className="border-b border-slate-200 flex gap-6 px-4">
          {(["milestones", "blockers", "history"] as Tab[]).map((t) => (
            <button
              key={t}
              onClick={() => setTab(t)}
              className={`py-3 text-sm capitalize ${
                tab === t ? "border-b-2 border-slate-900 font-semibold" : "text-slate-500"
              }`}
            >
              {t}
            </button>
          ))}
        </div>
        <div className="p-4">
          {tab === "milestones" && report && <MilestoneList items={report.milestones} />}
          {tab === "blockers"   && report && <BlockerList   items={report.blockers} />}
          {tab === "history"    && <RAGTrendChart data={history} />}
        </div>
      </div>

      <div className="rounded-lg border border-slate-200 bg-white p-4 space-y-3">
        <div className="text-xs uppercase tracking-wide text-slate-500">Supervisor notes</div>
        <ul className="space-y-2">
          {report?.notes.map((n) => (
            <li key={n.id} className="text-sm">
              <span className="text-slate-500 text-xs mr-2">
                {new Date(n.created_at).toLocaleString()} {n.supervisor_name ? `· ${n.supervisor_name}` : ""}
              </span>
              {n.note_text}
            </li>
          ))}
          {!report?.notes.length && <li className="text-slate-500 text-sm">No notes yet.</li>}
        </ul>
        <div className="flex gap-2">
          <input
            value={noteDraft}
            onChange={(e) => setNoteDraft(e.target.value)}
            placeholder="Add a note…"
            className="flex-1 px-3 py-2 border border-slate-300 rounded text-sm"
          />
          <button
            onClick={addNote}
            className="px-3 py-2 text-sm rounded bg-slate-900 text-white hover:bg-slate-700"
          >
            Add
          </button>
        </div>
      </div>
    </div>
  );
}
