import { useState, useCallback, useEffect } from "react";
import {
  ReactFlow,
  ReactFlowProvider,
  Background,
  Controls,
  useReactFlow,
  type OnConnect,
  type Connection,
} from "@xyflow/react";
import "@xyflow/react/dist/style.css";

import { useBoardSession } from "@/hooks/use-board-session";
import { useBoardPresence } from "@/hooks/use-board-presence";
import { useChatState } from "@/hooks/use-chat-state";
import { UniversalInput } from "@/components/chat/universal-input";
import { GraphChatCard } from "@/components/chat/chat-card";
import { BoardCustomNode } from "./board-custom-node";
import { BoardCustomEdge } from "./board-custom-edge";
import { BoardSourceNode } from "./board-source-node";
import { BoardSessionHeader } from "./board-session-header";
import { BoardEmptyState } from "./board-empty-state";
import { BoardCursorOverlay } from "./board-cursor-overlay";
import { BatchPromoteDialog } from "./batch-promote-dialog";
import { BoardChatView } from "./board-chat-view";

export type BoardView = "canvas" | "chat";

const nodeTypes = {
  boardNode: BoardCustomNode,
  sourceNode: BoardSourceNode,
};

const edgeTypes = {
  boardEdge: BoardCustomEdge,
};

type BoardWorkspaceInnerProps = {
  projectId: number;
  sessionId: number;
};

function BoardWorkspaceInner({ projectId, sessionId }: BoardWorkspaceInnerProps) {
  const {
    session,
    boardNodes,
    flowNodes,
    flowEdges,
    loading,
    channel,
    onNodesChange,
    onEdgesChange,
    setSession,
  } = useBoardSession(projectId, sessionId);

  const { participants, cursors, typingUsers, sendCursorPosition } = useBoardPresence(channel);
  const { screenToFlowPosition } = useReactFlow();

  // Chat integration — shared between canvas and chat views
  const chatState = useChatState(projectId, "strategist");
  const {
    chatTabs,
    activeTabIndex,
    activeTab,
    chatCardOpen,
    chatCardMinimized,
    setChatCardOpen,
    setChatCardMinimized,
    handleChatSubmit,
    handleAgentChange,
    handleAddTab,
    handleTabClick,
  } = chatState;

  const [view, setView] = useState<BoardView>(() => {
    const saved = localStorage.getItem(`board-view-${sessionId}`);
    return saved === "chat" ? "chat" : "canvas";
  });

  // Persist view preference per session
  useEffect(() => {
    localStorage.setItem(`board-view-${sessionId}`, view);
  }, [view, sessionId]);
  const [showPromoteDialog, setShowPromoteDialog] = useState(false);

  const draftCount = boardNodes.filter((n) => n.status === "draft").length;

  // Keyboard shortcut: Cmd/Ctrl + . to toggle views
  useEffect(() => {
    function handleKeyDown(e: KeyboardEvent) {
      if ((e.metaKey || e.ctrlKey) && e.key === ".") {
        e.preventDefault();
        setView((v) => (v === "canvas" ? "chat" : "canvas"));
      }
    }

    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, []);

  const handleMouseMove = useCallback(
    (event: React.MouseEvent) => {
      try {
        const pos = screenToFlowPosition({ x: event.clientX, y: event.clientY });
        sendCursorPosition(pos);
      } catch {
        // screenToFlowPosition may fail if ReactFlow is not ready
      }
    },
    [screenToFlowPosition, sendCursorPosition],
  );

  const handleConnect: OnConnect = useCallback(
    (_connection: Connection) => {
      // Could create a board edge here
    },
    [],
  );

  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  function handleBoardCommand(_command: { type: string; nodeIds?: string[]; nodeId?: string }) {
    // Handle commands from chat card (e.g. highlight, focus)
  }

  if (loading || !session) {
    return <div className="flex h-full items-center justify-center text-muted-foreground">Loading session...</div>;
  }

  return (
    <div className="flex h-full flex-col">
      <BoardSessionHeader
        projectId={projectId}
        session={session}
        participants={participants}
        draftCount={draftCount}
        view={view}
        onViewChange={setView}
        onSessionUpdate={setSession}
        onPushToGraph={() => setShowPromoteDialog(true)}
      />

      {/* Canvas view — always mounted, hidden when chat active */}
      <div className={view === "canvas" ? "relative flex-1" : "hidden"} onMouseMove={handleMouseMove}>
        {flowNodes.length === 0 && <BoardEmptyState onSuggestion={() => {}} />}

        <ReactFlow
          nodes={flowNodes}
          edges={flowEdges}
          onNodesChange={onNodesChange}
          onEdgesChange={onEdgesChange}
          onConnect={handleConnect}
          nodeTypes={nodeTypes}
          edgeTypes={edgeTypes}
          fitView={false}
          panOnDrag
          nodesDraggable={session.status === "active"}
          minZoom={0.2}
          maxZoom={2}
          defaultViewport={{ x: 0, y: 0, zoom: 1 }}
          proOptions={{ hideAttribution: true }}
        >
          <Background color="hsl(var(--border))" gap={24} size={1} />
          <Controls
            position="bottom-left"
            showInteractive={false}
            className="[&>button]:border-[var(--border)]"
          />
        </ReactFlow>

        {/* Cursor overlay */}
        <BoardCursorOverlay cursors={cursors} participants={participants} typingUsers={typingUsers} />

        {/* Universal input — centered bottom */}
        <UniversalInput
          surface="board"
          projectId={projectId}
          onSubmit={handleChatSubmit}
          currentAgent={activeTab?.agent ?? "strategist"}
          onAgentChange={handleAgentChange}
        />

        {/* Chat card — floating bottom right */}
        {chatCardOpen && (
          <GraphChatCard
            tabs={chatTabs}
            activeIndex={activeTabIndex}
            minimized={chatCardMinimized}
            onTabClick={handleTabClick}
            onAddTab={handleAddTab}
            onMinimize={() => setChatCardMinimized(!chatCardMinimized)}
            onClose={() => setChatCardOpen(false)}
            onGraphCommand={handleBoardCommand}
            onSwitchToChat={() => setView("chat")}
          />
        )}
      </div>

      {/* Chat view — always mounted, hidden when canvas active */}
      <div className={view === "chat" ? "flex-1 flex flex-col min-h-0" : "hidden"}>
        <BoardChatView
          projectId={projectId}
          chatState={chatState}
        />
      </div>

      {/* Batch promote dialog */}
      <BatchPromoteDialog
        projectId={projectId}
        sessionId={sessionId}
        nodes={boardNodes}
        open={showPromoteDialog}
        onClose={() => setShowPromoteDialog(false)}
      />
    </div>
  );
}

type BoardWorkspaceProps = {
  projectId: number;
  sessionId: number;
};

export function BoardWorkspace({ projectId, sessionId }: BoardWorkspaceProps) {
  return (
    <ReactFlowProvider>
      <BoardWorkspaceInner projectId={projectId} sessionId={sessionId} />
    </ReactFlowProvider>
  );
}
