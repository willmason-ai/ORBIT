import { Routes, Route, Navigate } from "react-router-dom";
import { AuthenticatedTemplate, UnauthenticatedTemplate, useMsal } from "@azure/msal-react";
import { apiScopes } from "./lib/auth";
import NavBar from "./components/NavBar";
import TeamOverview from "./pages/TeamOverview";
import EmployeeDetail from "./pages/EmployeeDetail";
import ProjectDetail from "./pages/ProjectDetail";
import SearchView from "./pages/SearchView";
import MyProjects from "./pages/MyProjects";

function SignIn() {
  const { instance } = useMsal();
  return (
    <div className="flex flex-col items-center justify-center min-h-screen gap-6">
      <h1 className="text-4xl font-bold tracking-tight">ORBIT</h1>
      <p className="text-slate-600">Operations Reporting & Brief Intelligence Tracker</p>
      <button
        className="px-5 py-2 rounded-md bg-slate-900 text-white hover:bg-slate-700 transition"
        onClick={() => instance.loginRedirect({ scopes: apiScopes })}
      >
        Sign in with Microsoft
      </button>
    </div>
  );
}

export default function App() {
  return (
    <>
      <UnauthenticatedTemplate>
        <SignIn />
      </UnauthenticatedTemplate>
      <AuthenticatedTemplate>
        <NavBar />
        <main className="max-w-7xl mx-auto px-4 py-8">
          <Routes>
            <Route path="/" element={<TeamOverview />} />
            <Route path="/employees/:id" element={<EmployeeDetail />} />
            <Route path="/projects/:id" element={<ProjectDetail />} />
            <Route path="/search" element={<SearchView />} />
            <Route path="/me" element={<MyProjects />} />
            <Route path="*" element={<Navigate to="/" replace />} />
          </Routes>
        </main>
      </AuthenticatedTemplate>
    </>
  );
}
