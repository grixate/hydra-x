import { useCallback } from "react";
import {
  ReactFlow,
  Background,
  Controls,
  useReactFlow,
  type OnConnect,
  type OnNodesChange,
  type OnEdgesChange,
  type Connection,
  type Node,
  type Edge,
} from "@xyflow/react";
import type { BoardSession, BoardPresenceUser } from "@/types";
import { UniversalInput } from "@/components/chat/universal-input";
import { BoardCustomNode } from "./board-custom-node";
import { BoardCustomEdge } from "./board-custom-edge";
import { BoardSourceNode } from "./board-source-node";
import { BoardCursorOverlay } from "./board-cursor-overlay";

const nodeTypes = {
  boardNode: BoardCustomNode,
  sourceNode: BoardSourceNode,
};

const edgeTypes = {
  boardEdge: BoardCustomEdge,
};

interface BoardCanvasPaneProps {
  projectId: number;
  session: BoardSession;
  flowNodes: Node[];
  flowEdges: Edge[];
  onNodesChange: OnNodesChange;
  onEdgesChange: OnEdgesChange;
  participants: BoardPresenceUser[];
  cursors: Map<string, { x: number; y: number }>;
  typingUsers: Set<string>;
  sendCursorPosition: (pos: { x: number; y: number }) => void;
  onChatSubmit: (message: string, agent: string, contextNodeIds: string[]) => Promise<void>;
  currentAgent: string;
  onAgentChange: (agent: string) => void;
}

export function BoardCanvasPane({
  projectId,
  session,
  flowNodes,
  flowEdges,
  onNodesChange,
  onEdgesChange,
  participants,
  cursors,
  typingUsers,
  sendCursorPosition,
  onChatSubmit,
  currentAgent,
  onAgentChange,
}: BoardCanvasPaneProps) {
  const { screenToFlowPosition } = useReactFlow();

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

  return (
    <div className="relative h-full" onMouseMove={handleMouseMove}>
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
          position="top-right"
          showInteractive={false}
          className="[&>button]:border-[var(--border)]"
        />
      </ReactFlow>

      <BoardCursorOverlay
        cursors={cursors}
        participants={participants}
        typingUsers={typingUsers}
      />

      <UniversalInput
        surface="board"
        projectId={projectId}
        onSubmit={onChatSubmit}
        currentAgent={currentAgent}
        onAgentChange={onAgentChange}
      />
    </div>
  );
}
