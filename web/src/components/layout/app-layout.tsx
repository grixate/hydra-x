import { Outlet } from "react-router-dom";
import { ProjectRail } from "./project-rail";
import { WorkspaceSidebar } from "./workspace-sidebar";
import { ToastContainer } from "@/components/ui/toast-notification";
import { NotificationBell } from "@/components/command-center/notification-bell";
import { ChatDock } from "@/components/chat/chat-dock";

export function AppLayout() {
  return (
    <div className="flex h-screen bg-background text-foreground">
      <ProjectRail />
      <WorkspaceSidebar />
      <main className="relative flex-1 overflow-auto">
        <NotificationBell />
        <Outlet />
      </main>
      <ChatDock />
      <ToastContainer />
    </div>
  );
}
