import React from "react";
import ReactDOM from "react-dom/client";
import { BrowserRouter, Routes, Route, Navigate } from "react-router-dom";
import { AppLayout } from "@/components/layout/app-layout";
import { StreamPage } from "@/pages/stream-page";
import { TrailPage } from "@/pages/trail-page";
import { SourcesPage } from "@/pages/sources-page";
import { ChatPage } from "@/pages/chat-page";
import { InsightsPage } from "@/pages/insights-page";
import { RequirementsPage } from "@/pages/requirements-page";
import { DecisionsPage } from "@/pages/project-decisions";
import { StrategiesPage } from "@/pages/project-strategies";
import { ArchitecturePage } from "@/pages/project-architecture";
import { DesignPage } from "@/pages/project-design";
import { TasksPage } from "@/pages/project-tasks";
import { LearningsPage } from "@/pages/project-learnings";
import { GraphHealthPage } from "@/pages/project-graph-health";
import { SettingsPage } from "@/pages/project-settings";
import { ProjectSelectPage } from "@/pages/project-select-page";
import "@/index.css";

ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <BrowserRouter>
      <Routes>
        <Route path="/product/:projectId" element={<AppLayout />}>
          <Route index element={<StreamPage />} />
          <Route path="stream" element={<StreamPage />} />
          <Route path="sources" element={<SourcesPage />} />
          <Route path="chat" element={<ChatPage />} />
          <Route path="chat/:conversationId" element={<ChatPage />} />
          <Route path="insights" element={<InsightsPage />} />
          <Route path="requirements" element={<RequirementsPage />} />
          <Route path="decisions" element={<DecisionsPage />} />
          <Route path="strategies" element={<StrategiesPage />} />
          <Route path="architecture" element={<ArchitecturePage />} />
          <Route path="design" element={<DesignPage />} />
          <Route path="tasks" element={<TasksPage />} />
          <Route path="learnings" element={<LearningsPage />} />
          <Route path="graph-health" element={<GraphHealthPage />} />
          <Route path="settings" element={<SettingsPage />} />
          <Route path="trail/:nodeType/:nodeId" element={<TrailPage />} />
        </Route>
        <Route path="/product" element={<ProjectSelectPage />} />
        <Route path="*" element={<Navigate to="/product" replace />} />
      </Routes>
    </BrowserRouter>
  </React.StrictMode>,
);
