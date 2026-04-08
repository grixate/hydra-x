import { useState, useCallback } from "react";
import { ReactFlowProvider } from "@xyflow/react";
import "@xyflow/react/dist/style.css";

import { useBoardSession } from "@/hooks/use-board-session";
import { useBoardPresence } from "@/hooks/use-board-presence";
import { useChatState } from "@/hooks/use-chat-state";
import { BoardSessionHeader } from "./board-session-header";
import { BoardCanvasPane } from "./board-canvas-pane";
import { BoardResponsePane } from "./board-response-pane";
import { ResizablePanes } from "./resizable-panes";
import { BatchPromoteDialog } from "./batch-promote-dialog";

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
  const chatState = useChatState(projectId, "strategist");

  const [showPromoteDialog, setShowPromoteDialog] = useState(false);
  const [rightCollapsed, setRightCollapsed] = useState(false);

  const draftCount = boardNodes.filter((n) => n.status === "draft").length;

  // Highlight a node on the canvas when clicked in the response pane
  const handleHighlightNode = useCallback((_nodeType: string, _nodeId: number) => {
    // TODO: implement canvas node highlighting + zoom-to-fit
  }, []);

  if (loading || !session) {
    return (
      <div className="flex h-full items-center justify-center text-muted-foreground">
        Loading session...
      </div>
    );
  }

  return (
    <div className="flex h-full flex-col">
      <BoardSessionHeader
        projectId={projectId}
        session={session}
        participants={participants}
        draftCount={draftCount}
        onSessionUpdate={setSession}
        onPushToGraph={() => setShowPromoteDialog(true)}
      />

      <ResizablePanes
        storageKey={`board-${sessionId}`}
        defaultSplit={0.55}
        rightCollapsed={rightCollapsed}
        onRightCollapsedChange={setRightCollapsed}
        left={
          <BoardCanvasPane
            projectId={projectId}
            session={session}
            flowNodes={flowNodes}
            flowEdges={flowEdges}
            onNodesChange={onNodesChange}
            onEdgesChange={onEdgesChange}
            participants={participants}
            cursors={cursors}
            typingUsers={typingUsers}
            sendCursorPosition={sendCursorPosition}
            onChatSubmit={chatState.handleChatSubmit}
            currentAgent={chatState.activeTab?.agent ?? "strategist"}
            onAgentChange={chatState.handleAgentChange}
          />
        }
        right={
          <BoardResponsePane
            projectId={projectId}
            chatState={chatState}
            onCollapse={() => setRightCollapsed(true)}
            onHighlightNode={handleHighlightNode}
          />
        }
      />

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
