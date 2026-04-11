import { Link, useNavigate } from "react-router-dom";
import { useMsal } from "@azure/msal-react";
import { Search, LogOut } from "lucide-react";
import { useState } from "react";

export default function NavBar() {
  const { instance, accounts } = useMsal();
  const navigate = useNavigate();
  const [q, setQ] = useState("");

  const user = accounts[0];

  function onSearch(e: React.FormEvent) {
    e.preventDefault();
    if (q.trim()) navigate(`/search?q=${encodeURIComponent(q.trim())}`);
  }

  return (
    <header className="bg-white border-b border-slate-200">
      <div className="max-w-7xl mx-auto px-4 h-14 flex items-center gap-6">
        <Link to="/" className="font-bold text-xl tracking-tight">ORBIT</Link>
        <form onSubmit={onSearch} className="flex-1 max-w-md">
          <div className="relative">
            <Search className="absolute left-3 top-2.5 w-4 h-4 text-slate-400" />
            <input
              value={q}
              onChange={(e) => setQ(e.target.value)}
              placeholder="Search projects, blockers, narratives…"
              className="w-full pl-9 pr-3 py-2 rounded-md bg-slate-100 focus:bg-white border border-transparent focus:border-slate-300 focus:outline-none text-sm"
            />
          </div>
        </form>
        <div className="ml-auto flex items-center gap-4 text-sm">
          <span className="text-slate-700">{user?.name ?? user?.username}</span>
          <button
            onClick={() => instance.logoutRedirect()}
            className="inline-flex items-center gap-1 text-slate-500 hover:text-slate-900"
            title="Sign out"
          >
            <LogOut className="w-4 h-4" />
          </button>
        </div>
      </div>
    </header>
  );
}
