import { Outlet } from "react-router-dom";
import { WorkspaceSidebar } from "./workspace-sidebar";

export function AppLayout() {
  return (
    <div className="flex h-screen bg-[var(--paper)] text-[var(--ink)]">
      <WorkspaceSidebar />
      <main className="flex-1 overflow-auto">
        <Outlet />
      </main>
    </div>
  );
}
