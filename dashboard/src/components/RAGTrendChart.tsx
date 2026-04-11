import { LineChart, Line, XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid } from "recharts";

interface HistoryRow {
  id: number;
  submission_at: string;
  pct_hours_consumed: number | null;
  rag_status: "RED" | "AMBER" | "GREEN" | null;
}

export default function RAGTrendChart({ data }: { data: HistoryRow[] }) {
  if (!data.length) return <p className="text-slate-500 text-sm">No history yet.</p>;
  const chartData = [...data]
    .reverse()
    .map((r) => ({
      date: new Date(r.submission_at).toLocaleDateString(),
      pct: r.pct_hours_consumed ?? 0,
    }));
  return (
    <div className="h-56">
      <ResponsiveContainer>
        <LineChart data={chartData}>
          <CartesianGrid strokeDasharray="3 3" stroke="#e5e7eb" />
          <XAxis dataKey="date" tick={{ fontSize: 12 }} />
          <YAxis tick={{ fontSize: 12 }} unit="%" />
          <Tooltip />
          <Line type="monotone" dataKey="pct" stroke="#0f172a" strokeWidth={2} dot={{ r: 3 }} />
        </LineChart>
      </ResponsiveContainer>
    </div>
  );
}
