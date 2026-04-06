import React from "react";
import ReactDOM from "react-dom/client";
import { BrowserRouter, Routes, Route, Navigate } from "react-router-dom";
import { AppLayout } from "@/components/layout/app-layout";
import { LandingLayout } from "@/components/layout/landing-layout";
import { StreamPage } from "@/pages/stream-page";
import { GraphPage } from "@/pages/graph-page";
import { BoardPage } from "@/pages/board-page";
import { TasksPage } from "@/pages/project-tasks";
import { TrailPage } from "@/pages/trail-page";
import { SimulationPage } from "@/pages/simulation-page";
import { AgentListPage } from "@/pages/agent-list-page";
import { AgentChatPage } from "@/pages/agent-chat-page";
import { SettingsPage } from "@/pages/project-settings";
import { ProjectSelectPage } from "@/pages/project-select-page";
import "@/index.css";

ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <BrowserRouter>
      <Routes>
        {/* Project-scoped routes — full layout with rail + sidebar + content */}
        <Route path="/projects/:projectId" element={<AppLayout />}>
          <Route index element={<StreamPage />} />
          <Route path="stream" element={<StreamPage />} />
          <Route path="graph" element={<GraphPage />} />
          <Route path="board" element={<BoardPage />} />
          <Route path="board/:sessionId" element={<BoardPage />} />
          <Route path="tasks" element={<TasksPage />} />
          <Route path="simulation" element={<SimulationPage />} />
          <Route path="chat" element={<AgentListPage />} />
          <Route path="chat/:persona" element={<AgentChatPage />} />
          <Route path="trail/:nodeType/:nodeId" element={<TrailPage />} />
          <Route path="settings" element={<SettingsPage />} />
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

        {/* Legacy redirect */}
        <Route path="/product" element={<Navigate to="/" replace />} />

        {/* Fallback */}
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </BrowserRouter>
  </React.StrictMode>,
);
