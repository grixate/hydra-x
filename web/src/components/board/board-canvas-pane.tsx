import { useState, useCallback, useRef } from "react";
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
import { motion, AnimatePresence } from "motion/react";
import type { BoardSession, BoardPresenceUser } from "@/types";
import { api } from "@/lib/api";
import { UniversalInput } from "@/components/chat/universal-input";
import { BoardCustomNode } from "./board-custom-node";
import { BoardCustomEdge } from "./board-custom-edge";
import { BoardSourceNode } from "./board-source-node";
import { BoardCursorOverlay } from "./board-cursor-overlay";
import { Loader2, Check, X as XIcon } from "lucide-react";

const nodeTypes = {
  boardNode: BoardCustomNode,
  sourceNode: BoardSourceNode,
};

const edgeTypes = {
  boardEdge: BoardCustomEdge,
};

type UploadStatus = {
  id: string;
  filename: string;
  status: "uploading" | "analyzing" | "done" | "error";
};

interface BoardCanvasPaneProps {
  projectId: number;
  sessionId: number;
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
  sessionId,
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
  const [dragOver, setDragOver] = useState(false);
  const [dragFileCount, setDragFileCount] = useState(0);
  const dragCounterRef = useRef(0);
  const [uploads, setUploads] = useState<UploadStatus[]>([]);

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
    (_connection: Connection) => {},
    [],
  );

  const handleDragEnter = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    dragCounterRef.current++;
    setDragOver(true);
    setDragFileCount(e.dataTransfer.items.length);
  }, []);

  const handleDragOver = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    e.dataTransfer.dropEffect = "copy";
  }, []);

  const handleDragLeave = useCallback(() => {
    dragCounterRef.current--;
    if (dragCounterRef.current === 0) setDragOver(false);
  }, []);

  const updateUpload = useCallback((id: string, status: UploadStatus["status"]) => {
    setUploads((prev) => prev.map((u) => (u.id === id ? { ...u, status } : u)));
    // Auto-remove completed/error items after 3s
    if (status === "done" || status === "error") {
      setTimeout(() => {
        setUploads((prev) => prev.filter((u) => u.id !== id));
      }, 3000);
    }
  }, []);

  const handleDrop = useCallback(
    async (e: React.DragEvent) => {
      e.preventDefault();
      dragCounterRef.current = 0;
      setDragOver(false);

      const files = Array.from(e.dataTransfer.files);
      if (files.length === 0) return;

      let position: { x: number; y: number };
      try {
        position = screenToFlowPosition({ x: e.clientX, y: e.clientY });
      } catch {
        position = { x: 100, y: 100 };
      }

      // Add all files to the upload status bar
      const uploadEntries: UploadStatus[] = files.map((f, i) => ({
        id: `upload-${Date.now()}-${i}`,
        filename: f.name,
        status: "uploading" as const,
      }));
      setUploads((prev) => [...prev, ...uploadEntries]);

      for (let i = 0; i < files.length; i++) {
        const file = files[i];
        const uploadId = uploadEntries[i].id;
        try {
          const source = await api.createSource(projectId, {
            title: file.name,
            sourceType: "document",
            file,
          });

          updateUpload(uploadId, "analyzing");

          await api.createBoardNode(projectId, sessionId, {
            node_type: "source_ref",
            title: source.title || file.name,
            body: `${file.name} — processing`,
            created_by: "human",
            metadata: {
              source_id: source.id,
              source_type: "file",
              filename: file.name,
              processing_status: source.processing_status,
              position: {
                x: position.x + (i % 2) * 340,
                y: position.y + Math.floor(i / 2) * 180,
              },
            },
          });

          api.analyzeSource(projectId, source.id, sessionId).catch(() => {});
          updateUpload(uploadId, "done");
        } catch {
          updateUpload(uploadId, "error");
        }
      }
    },
    [projectId, sessionId, screenToFlowPosition, updateUpload],
  );

  return (
    <div
      className="relative h-full"
      onMouseMove={handleMouseMove}
      onDragEnter={handleDragEnter}
      onDragOver={handleDragOver}
      onDragLeave={handleDragLeave}
      onDrop={handleDrop}
    >
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

      {/* Upload status bar — top of canvas */}
      <AnimatePresence>
        {uploads.length > 0 && (
          <motion.div
            initial={{ opacity: 0, y: -20 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -20 }}
            transition={{ duration: 0.2 }}
            className="absolute top-3 left-3 z-20 space-y-1.5 max-w-xs"
          >
            {uploads.map((u) => (
              <motion.div
                key={u.id}
                initial={{ opacity: 0, x: -12 }}
                animate={{ opacity: 1, x: 0 }}
                exit={{ opacity: 0, x: -12 }}
                className="flex items-center gap-2 rounded-lg border bg-background/95 backdrop-blur-sm px-3 py-1.5 shadow-sm"
              >
                {u.status === "uploading" && <Loader2 className="h-3 w-3 animate-spin text-primary shrink-0" />}
                {u.status === "analyzing" && <Loader2 className="h-3 w-3 animate-spin text-amber-500 shrink-0" />}
                {u.status === "done" && <Check className="h-3 w-3 text-green-500 shrink-0" />}
                {u.status === "error" && <XIcon className="h-3 w-3 text-destructive shrink-0" />}
                <span className="text-xs truncate max-w-[180px]">{u.filename}</span>
                <span className="text-[10px] text-muted-foreground shrink-0">
                  {u.status === "uploading" ? "uploading" : u.status === "analyzing" ? "analyzing" : u.status === "done" ? "done" : "failed"}
                </span>
              </motion.div>
            ))}
          </motion.div>
        )}
      </AnimatePresence>

      <UniversalInput
        surface="board"
        projectId={projectId}
        onSubmit={onChatSubmit}
        currentAgent={currentAgent}
        onAgentChange={onAgentChange}
      />

      {/* Drop zone overlay */}
      {dragOver && (
        <div className="pointer-events-none absolute inset-0 z-50 flex items-center justify-center rounded-xl border-2 border-dashed border-primary/40 bg-primary/5">
          <div className="text-center">
            <p className="text-sm font-medium text-primary/60">
              Drop {dragFileCount > 0 ? `${dragFileCount} file${dragFileCount > 1 ? "s" : ""}` : "files"} to add to this session
            </p>
            <p className="mt-1 text-xs text-primary/40">
              Agents will analyze them automatically
            </p>
            {dragFileCount > 5 && (
              <p className="mt-2 text-xs text-amber-500/70">
                For large imports (10+ files), consider using bulk import from the + menu
              </p>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
