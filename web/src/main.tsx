import React from "react";
import ReactDOM from "react-dom/client";
import { BrowserRouter, Routes, Route, Navigate } from "react-router-dom";
import { AppLayout } from "@/components/layout/app-layout";
import { StreamPage } from "@/pages/stream-page";
import { GraphPage } from "@/pages/graph-page";
import { BoardPage } from "@/pages/board-page";
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
        <Route path="/projects/:projectId" element={<AppLayout />}>
          <Route index element={<StreamPage />} />
          <Route path="stream" element={<StreamPage />} />
          <Route path="graph" element={<GraphPage />} />
          <Route path="board" element={<BoardPage />} />
          <Route path="simulation" element={<SimulationPage />} />
          <Route path="chat" element={<AgentListPage />} />
          <Route path="chat/:persona" element={<AgentChatPage />} />
          <Route path="trail/:nodeType/:nodeId" element={<TrailPage />} />
          <Route path="settings" element={<SettingsPage />} />
        </Route>
        <Route path="/product" element={<ProjectSelectPage />} />
        <Route path="*" element={<Navigate to="/product" replace />} />
      </Routes>
    </BrowserRouter>
  </React.StrictMode>,
);
