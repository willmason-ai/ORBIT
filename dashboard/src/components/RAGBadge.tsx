import { RAG, type RagStatus } from "../lib/rag";

export default function RAGBadge({ status }: { status: RagStatus | null | undefined }) {
  if (!status) {
    return (
      <span className="inline-flex items-center px-2 py-0.5 rounded text-xs border border-slate-300 text-slate-500">
        —
      </span>
    );
  }
  const c = RAG[status];
  return (
    <span className={`inline-flex items-center gap-1 px-2 py-0.5 rounded text-xs border ${c.bg} ${c.border} ${c.text}`}>
      <span aria-hidden>{c.emoji}</span>
      {c.label}
    </span>
  );
}
