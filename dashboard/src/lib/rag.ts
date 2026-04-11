export type RagStatus = "RED" | "AMBER" | "GREEN";

export const RAG: Record<RagStatus, {
  bg: string;
  border: string;
  text: string;
  label: string;
  emoji: string;
}> = {
  RED:   { bg: "bg-red-100",   border: "border-red-500",   text: "text-red-700",   label: "RED",   emoji: "🔴" },
  AMBER: { bg: "bg-amber-100", border: "border-amber-500", text: "text-amber-700", label: "AMBER", emoji: "🟡" },
  GREEN: { bg: "bg-green-100", border: "border-green-500", text: "text-green-700", label: "GREEN", emoji: "🟢" },
} as const;
