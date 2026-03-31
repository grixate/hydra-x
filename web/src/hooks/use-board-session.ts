import { useState, useEffect, useCallback, useRef } from "react";
import type { Node, Edge, NodeChange, EdgeChange } from "@xyflow/react";
import { applyNodeChanges, applyEdgeChanges } from "@xyflow/react";
import { api } from "@/lib/api";
import { getSocket } from "@/lib/socket";
import type { BoardNode, BoardEdge, BoardSession } from "@/types";
import { BOARD_NODE_WIDTH } from "@/components/board/board-constants";

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type Channel = { push: (event: string, payload: any) => any; on: (event: string, callback: (payload: any) => void) => number; off: (event: string, ref?: number) => void; join: () => any; leave: () => void };

export function useBoardSession(projectId: number, sessionId: number) {
  const [session, setSession] = useState<BoardSession | null>(null);
  const [boardNodes, setBoardNodes] = useState<BoardNode[]>([]);
  const [boardEdges, setBoardEdges] = useState<BoardEdge[]>([]);
  const [flowNodes, setFlowNodes] = useState<Node[]>([]);
  const [flowEdges, setFlowEdges] = useState<Edge[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const channelRef = useRef<Channel | null>(null);
  const moveTimerRef = useRef<ReturnType<typeof setTimeout>>();

  // Convert board nodes to React Flow nodes
  const toFlowNodes = useCallback((nodes: BoardNode[]): Node[] => {
    return nodes.map((n, i) => {
      const pos = n.metadata?.position ?? {
        x: (i % 4) * (BOARD_NODE_WIDTH + 40) + 60,
        y: Math.floor(i / 4) * 180 + 100,
      };
      return {
        id: String(n.id),
        type: n.node_type === "source_ref" ? "sourceNode" : "boardNode",
        position: { x: pos.x, y: pos.y },
        data: n,
      };
    });
  }, []);

  // Convert board edges to React Flow edges
  const toFlowEdges = useCallback((edges: BoardEdge[]): Edge[] => {
    return edges.map((e) => ({
      id: String(e.id),
      source: String(e.from_board_node_id),
      target: String(e.to_board_node_id),
      type: "boardEdge",
      data: { kind: e.kind },
    }));
  }, []);

  // Load initial data
  useEffect(() => {
    let cancelled = false;

    async function load() {
      setLoading(true);
      setError(null);
      try {
        const [sess, nodes] = await Promise.all([
          api.getBoardSession(projectId, sessionId),
          api.listBoardNodes(projectId, sessionId),
        ]);
        if (cancelled) return;
        setSession(sess);
        setBoardNodes(nodes);
        setBoardEdges([]);
        setFlowNodes(toFlowNodes(nodes));
        setFlowEdges([]);
      } catch (err) {
        if (cancelled) return;
        setError(err instanceof Error ? err.message : "Failed to load session");
      } finally {
        if (!cancelled) setLoading(false);
      }
    }
    load();

    return () => { cancelled = true; };
  }, [projectId, sessionId, toFlowNodes, toFlowEdges]);

  // Join channel — track listener refs for cleanup
  useEffect(() => {
    const socket = getSocket();
    const channel = socket.channel(`board_session:${sessionId}`, {
      user_id: "operator",
      user_name: "Operator",
    });

    const refs: number[] = [];

    channel.join().receive("ok", () => {});

    refs.push(
      channel.on("board_node.created", ({ board_node }: { board_node: BoardNode }) => {
        setBoardNodes((prev) => {
          // Avoid duplicates if we already added this node optimistically
          if (prev.some((n) => n.id === board_node.id)) return prev;
          return [...prev, board_node];
        });
        setFlowNodes((prev) => {
          if (prev.some((n) => n.id === String(board_node.id))) return prev;
          return [
            ...prev,
            {
              id: String(board_node.id),
              type: board_node.node_type === "source_ref" ? "sourceNode" : "boardNode",
              position: board_node.metadata?.position ?? { x: 200, y: 200 },
              data: board_node,
            },
          ];
        });
      }),
    );

    refs.push(
      channel.on("board_node.updated", ({ board_node }: { board_node: BoardNode }) => {
        setBoardNodes((prev) => prev.map((n) => (n.id === board_node.id ? board_node : n)));
        setFlowNodes((prev) =>
          prev.map((n) =>
            n.id === String(board_node.id) ? { ...n, data: board_node } : n,
          ),
        );
      }),
    );

    refs.push(
      channel.on("board_node.promoted", ({ board_node }: { board_node: BoardNode }) => {
        setBoardNodes((prev) => prev.map((n) => (n.id === board_node.id ? board_node : n)));
        setFlowNodes((prev) =>
          prev.map((n) =>
            n.id === String(board_node.id) ? { ...n, data: board_node } : n,
          ),
        );
      }),
    );

    refs.push(
      channel.on("node_moved", ({ node_id, x, y }: { node_id: number; x: number; y: number }) => {
        setFlowNodes((prev) =>
          prev.map((n) =>
            n.id === String(node_id) ? { ...n, position: { x, y } } : n,
          ),
        );
      }),
    );

    refs.push(
      channel.on("reaction_toggled", ({ node_id, reactions }: { node_id: number; reactions: Record<string, string[]> }) => {
        setBoardNodes((prev) =>
          prev.map((n) =>
            n.id === node_id
              ? { ...n, metadata: { ...n.metadata, reactions } }
              : n,
          ),
        );
        setFlowNodes((prev) =>
          prev.map((n) => {
            if (n.id === String(node_id)) {
              const data = { ...(n.data as BoardNode), metadata: { ...(n.data as BoardNode).metadata, reactions } };
              return { ...n, data };
            }
            return n;
          }),
        );
      }),
    );

    channelRef.current = channel;

    return () => {
      // Unsubscribe all listeners before leaving
      for (const ref of refs) {
        channel.off("board_node.created", ref);
        channel.off("board_node.updated", ref);
        channel.off("board_node.promoted", ref);
        channel.off("node_moved", ref);
        channel.off("reaction_toggled", ref);
      }
      channel.leave();
      channelRef.current = null;
    };
  }, [sessionId]);

  // Clear debounce timer on unmount
  useEffect(() => {
    return () => { clearTimeout(moveTimerRef.current); };
  }, []);

  // Handle React Flow node changes (includes drag)
  const onNodesChange = useCallback(
    (changes: NodeChange[]) => {
      setFlowNodes((prev) => applyNodeChanges(changes, prev));

      // Debounce position persistence for drag events
      for (const change of changes) {
        if (change.type === "position" && change.position && !change.dragging) {
          const nodeId = parseInt(change.id);
          const { x, y } = change.position;

          clearTimeout(moveTimerRef.current);
          moveTimerRef.current = setTimeout(() => {
            channelRef.current?.push("node_moved", { node_id: nodeId, x, y });
          }, 100);
        }
      }
    },
    [],
  );

  const onEdgesChange = useCallback(
    (changes: EdgeChange[]) => {
      setFlowEdges((prev) => applyEdgeChanges(changes, prev));
    },
    [],
  );

  // Actions
  const promoteNode = useCallback(
    async (nodeId: number) => {
      await api.promoteBoardNode(projectId, sessionId, nodeId);
    },
    [projectId, sessionId],
  );

  const discardNode = useCallback(
    async (nodeId: number) => {
      await api.updateBoardNode(projectId, sessionId, nodeId, { status: "discarded" } as Partial<BoardNode>);
    },
    [projectId, sessionId],
  );

  const toggleReaction = useCallback(
    (nodeId: number, reaction: string) => {
      channelRef.current?.push("reaction_toggled", { node_id: nodeId, reaction });
    },
    [],
  );

  const addNode = useCallback(
    async (payload: { node_type: string; title: string; body: string; metadata?: Record<string, unknown> }) => {
      return api.createBoardNode(projectId, sessionId, {
        ...payload,
        created_by: "human",
      });
    },
    [projectId, sessionId],
  );

  const channel = channelRef.current;

  return {
    session,
    boardNodes,
    boardEdges,
    flowNodes,
    flowEdges,
    loading,
    error,
    channel,
    onNodesChange,
    onEdgesChange,
    promoteNode,
    discardNode,
    toggleReaction,
    addNode,
    setSession,
  };
}
