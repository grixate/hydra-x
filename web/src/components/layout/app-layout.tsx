import { Outlet } from "react-router-dom";
import { WorkspaceSidebar } from "./workspace-sidebar";
import { ToastContainer } from "@/components/ui/toast-notification";

export function AppLayout() {
  return (
    <div className="flex h-screen bg-background text-foreground">
      <WorkspaceSidebar />
      <main className="flex-1 overflow-auto">
        <Outlet />
      </main>
      <ToastContainer />
    </div>
  );
}
