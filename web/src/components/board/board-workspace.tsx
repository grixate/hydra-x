import { useState, useCallback } from "react";
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
import { BoardCustomNode } from "./board-custom-node";
import { BoardCustomEdge } from "./board-custom-edge";
import { BoardSourceNode } from "./board-source-node";
import { BoardSessionHeader } from "./board-session-header";
import { BoardEmptyState } from "./board-empty-state";
import { BoardCursorOverlay } from "./board-cursor-overlay";
import { BatchPromoteDialog } from "./batch-promote-dialog";
import { NODE_TYPE_LABELS } from "./board-constants";
import type { BoardNode } from "@/types";

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
    promoteNode,
    discardNode,
    addNode,
    setSession,
  } = useBoardSession(projectId, sessionId);

  const { participants, cursors, typingUsers, sendCursorPosition } = useBoardPresence(channel);
  const { screenToFlowPosition } = useReactFlow();

  const [showPromoteDialog, setShowPromoteDialog] = useState(false);
  const [showAddNode, setShowAddNode] = useState(false);
  const [newNodeType, setNewNodeType] = useState("insight");
  const [newNodeTitle, setNewNodeTitle] = useState("");
  const [newNodeBody, setNewNodeBody] = useState("");

  const draftCount = boardNodes.filter((n) => n.status === "draft").length;

  const handleMouseMove = useCallback(
    (event: React.MouseEvent) => {
      const pos = screenToFlowPosition({ x: event.clientX, y: event.clientY });
      sendCursorPosition(pos);
    },
    [screenToFlowPosition, sendCursorPosition],
  );

  const handleConnect: OnConnect = useCallback(
    (_connection: Connection) => {
      // Could create a board edge here
    },
    [],
  );

  async function handleAddNode() {
    if (!newNodeTitle.trim()) return;
    await addNode({
      node_type: newNodeType,
      title: newNodeTitle.trim(),
      body: newNodeBody.trim(),
    });
    setNewNodeTitle("");
    setNewNodeBody("");
    setShowAddNode(false);
  }

  function handleSuggestion(text: string) {
    // TODO: Send as chat message to strategist
    console.log("Suggestion:", text);
  }

  if (loading || !session) {
    return <div className="flex h-full items-center justify-center text-zinc-600">Loading session...</div>;
  }

  return (
    <div className="flex h-full flex-col">
      <BoardSessionHeader
        projectId={projectId}
        session={session}
        participants={participants}
        draftCount={draftCount}
        onSessionUpdate={setSession}
        onPromoteAll={() => setShowPromoteDialog(true)}
      />

      <div className="relative flex-1" onMouseMove={handleMouseMove}>
        {flowNodes.length === 0 && <BoardEmptyState onSuggestion={handleSuggestion} />}

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
          <Background color="#27272a" gap={24} size={1} />
          <Controls
            position="bottom-left"
            showInteractive={false}
            className="!bg-zinc-900 !border-zinc-800 !shadow-lg [&>button]:!bg-zinc-800 [&>button]:!border-zinc-700 [&>button]:!text-zinc-400 [&>button:hover]:!bg-zinc-700"
          />
        </ReactFlow>

        {/* Cursor overlay */}
        <BoardCursorOverlay cursors={cursors} participants={participants} typingUsers={typingUsers} />

        {/* Floating add-node button */}
        {session.status === "active" && (
          <div className="absolute bottom-4 left-1/2 z-20 -translate-x-1/2">
            {!showAddNode ? (
              <button
                onClick={() => setShowAddNode(true)}
                className="rounded-xl border border-zinc-700 bg-zinc-900/90 px-6 py-3 text-xs text-zinc-400 hover:border-zinc-500 hover:text-white transition backdrop-blur-sm shadow-lg"
              >
                + Add a node
              </button>
            ) : (
              <div className="w-96 rounded-xl border border-zinc-700 bg-zinc-950/95 p-4 shadow-2xl backdrop-blur-sm">
                <div className="flex gap-2 mb-3">
                  <select
                    value={newNodeType}
                    onChange={(e) => setNewNodeType(e.target.value)}
                    className="rounded-lg border border-zinc-700 bg-zinc-800 px-3 py-1.5 text-xs text-white"
                  >
                    {Object.entries(NODE_TYPE_LABELS)
                      .filter(([k]) => k !== "source_ref")
                      .map(([key, label]) => (
                        <option key={key} value={key}>
                          {label}
                        </option>
                      ))}
                  </select>
                  <input
                    value={newNodeTitle}
                    onChange={(e) => setNewNodeTitle(e.target.value)}
                    onKeyDown={(e) => e.key === "Enter" && handleAddNode()}
                    placeholder="Node title..."
                    autoFocus
                    className="flex-1 rounded-lg border border-zinc-700 bg-zinc-800 px-3 py-1.5 text-sm text-white placeholder-zinc-600 focus:border-orange-500 focus:outline-none"
                  />
                </div>
                <textarea
                  value={newNodeBody}
                  onChange={(e) => setNewNodeBody(e.target.value)}
                  placeholder="Description..."
                  rows={2}
                  className="w-full rounded-lg border border-zinc-700 bg-zinc-800 px-3 py-1.5 text-sm text-white placeholder-zinc-600 focus:border-orange-500 focus:outline-none resize-none"
                />
                <div className="mt-3 flex justify-end gap-2">
                  <button
                    onClick={() => setShowAddNode(false)}
                    className="rounded-lg border border-zinc-700 px-3 py-1.5 text-xs text-zinc-500 hover:text-white transition"
                  >
                    Cancel
                  </button>
                  <button
                    onClick={handleAddNode}
                    className="rounded-lg bg-orange-600 px-4 py-1.5 text-xs font-medium text-white hover:bg-orange-500 transition"
                  >
                    Create
                  </button>
                </div>
              </div>
            )}
          </div>
        )}
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
