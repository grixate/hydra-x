import React from "react";
import ReactDOM from "react-dom/client";
import { BrowserRouter, Routes, Route, Navigate } from "react-router-dom";

// Global diagnostics — make sure NOTHING that goes wrong is silent.
// Async errors and unhandled rejections don't reach React error boundaries;
// these listeners give us a console trail when the surface goes blank.
if (typeof window !== "undefined") {
  window.addEventListener("error", (event) => {
    // eslint-disable-next-line no-console
    console.error(
      "[hydra:window.error]",
      event.message,
      "at",
      `${event.filename}:${event.lineno}:${event.colno}`,
      event.error,
    );
  });
  window.addEventListener("unhandledrejection", (event) => {
    // eslint-disable-next-line no-console
    console.error("[hydra:unhandledrejection]", event.reason);
  });
}
import { AppLayout } from "@/components/layout/app-layout";
import { LandingLayout } from "@/components/layout/landing-layout";
import { StreamPage } from "@/pages/stream-page";
import { CommandCenterPage } from "@/pages/command-center-page";
import { GraphPage } from "@/pages/graph-page";
import { BoardPage } from "@/pages/board-page";
import { TasksPage } from "@/pages/project-tasks";
import { TrailPage } from "@/pages/trail-page";
import { SimulationPage } from "@/pages/simulation-page";
import { SimulationConfigurePage } from "@/pages/simulation-configure-page";
import { SimulationDetailPage } from "@/pages/simulation-detail-page";
import { AgentPage } from "@/pages/agent-page";
import { SettingsPage } from "@/pages/project-settings";
import { CoherencePage } from "@/pages/coherence-page";
import { WatchPage } from "@/pages/watch-page";
import { BulkImportPage } from "@/pages/bulk-import-page";
import { UsagePage } from "@/pages/usage-page";
import { LibraryPage } from "@/pages/library-page";
import { LibraryDetailPage } from "@/pages/library-detail-page";
import { ProjectSelectPage } from "@/pages/project-select-page";
import { AuthPage } from "@/pages/auth-page";
import "@/index.css";

ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <BrowserRouter>
      <Routes>
        {/* Project-scoped routes — full layout with rail + sidebar + content */}
        <Route path="/projects/:projectId" element={<AppLayout />}>
          <Route index element={<StreamPage />} />
          <Route path="stream" element={<StreamPage />} />
          <Route path="command-center" element={<CommandCenterPage />} />
          <Route path="graph" element={<GraphPage />} />
          <Route path="board" element={<BoardPage />} />
          <Route path="board/:sessionId" element={<BoardPage />} />
          <Route path="tasks" element={<TasksPage />} />
          <Route path="coherence" element={<CoherencePage />} />
          <Route path="watch" element={<WatchPage />} />
          <Route path="simulation" element={<SimulationPage />} />
          <Route path="simulation/new" element={<SimulationConfigurePage />} />
          <Route path="simulation/:simId" element={<SimulationDetailPage />} />
          <Route path="library" element={<LibraryPage />} />
          <Route path="library/:artifactId" element={<LibraryDetailPage />} />
          <Route path="usage" element={<UsagePage />} />
          <Route path="agents/:persona" element={<AgentPage />} />
          <Route path="trail/:nodeType/:nodeId" element={<TrailPage />} />
          <Route path="settings" element={<SettingsPage />} />
          <Route path="import" element={<BulkImportPage />} />
        </Route>

        {/* No project selected — show rail + landing */}
        <Route path="/" element={<LandingLayout />} />

        {/* New project creation */}
        <Route path="/projects/new" element={<ProjectSelectPage />} />

        {/* Account settings (not project-scoped) — placeholder until full page exists */}
        <Route
          path="/account"
          element={
            <div className="flex h-screen items-center justify-center bg-background text-foreground">
              <div className="text-center">
                <h1 className="text-xl font-semibold">Account Settings</h1>
                <p className="mt-2 text-sm text-muted-foreground">Coming soon.</p>
              </div>
            </div>
          }
        />

        {/* Auth */}
        <Route path="/auth" element={<AuthPage />} />

        {/* Legacy redirect */}
        <Route path="/product" element={<Navigate to="/" replace />} />

        {/* Fallback */}
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </BrowserRouter>
  </React.StrictMode>,
);
