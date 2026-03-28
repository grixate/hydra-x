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
import { StubPage } from "@/pages/stub-page";
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
          <Route path="decisions" element={<StubPage title="Decisions" />} />
          <Route
            path="strategies"
            element={<StubPage title="Strategies" />}
          />
          <Route
            path="architecture"
            element={<StubPage title="Architecture" />}
          />
          <Route path="design" element={<StubPage title="Design" />} />
          <Route path="tasks" element={<StubPage title="Tasks" />} />
          <Route path="learnings" element={<StubPage title="Learnings" />} />
          <Route
            path="graph-health"
            element={<StubPage title="Graph Health" />}
          />
          <Route path="settings" element={<StubPage title="Settings" />} />
          <Route
            path="trail/:nodeType/:nodeId"
            element={<TrailPage />}
          />
        </Route>
        <Route path="*" element={<Navigate to="/product/1" replace />} />
      </Routes>
    </BrowserRouter>
  </React.StrictMode>,
);
