import { useState, useEffect, useCallback, useRef } from "react";
import type { BoardNodePosition, BoardPresenceUser } from "@/types";
import { PRESENCE_COLORS } from "@/components/board/board-constants";

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type Channel = { push: (event: string, payload: any) => any; on: (event: string, callback: (payload: any) => void) => number; off: (event: string, ref?: number) => void };

export function useBoardPresence(channel: Channel | null) {
  const [participants, setParticipants] = useState<BoardPresenceUser[]>([]);
  const [cursors, setCursors] = useState<Map<string, BoardNodePosition>>(new Map());
  const [typingUsers, setTypingUsers] = useState<Set<string>>(new Set());
  const lastSentRef = useRef(0);

  useEffect(() => {
    if (!channel) return;

    const refs: Array<{ event: string; ref: number }> = [];

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    refs.push({ event: "presence_state", ref: channel.on("presence_state", (state: any) => {
      const users = Object.entries(state).map(([userId, data]: [string, any], i) => ({
        user_id: userId,
        name: data.metas?.[0]?.name ?? userId,
        color: PRESENCE_COLORS[i % PRESENCE_COLORS.length],
        joined_at: data.metas?.[0]?.joined_at ?? new Date().toISOString(),
      }));
      setParticipants(users);
    })});

    refs.push({ event: "cursor_move", ref: channel.on("cursor_move", (payload: { user_id: string; x: number; y: number }) => {
      setCursors((prev) => {
        const next = new Map(prev);
        next.set(payload.user_id, { x: payload.x, y: payload.y });
        return next;
      });
    })});

    refs.push({ event: "typing_start", ref: channel.on("typing_start", (payload: { user_id: string }) => {
      setTypingUsers((prev) => new Set(prev).add(payload.user_id));
    })});

    refs.push({ event: "typing_stop", ref: channel.on("typing_stop", (payload: { user_id: string }) => {
      setTypingUsers((prev) => {
        const next = new Set(prev);
        next.delete(payload.user_id);
        return next;
      });
    })});

    return () => {
      for (const { event, ref } of refs) {
        channel.off(event, ref);
      }
    };
  }, [channel]);

  const sendCursorPosition = useCallback(
    (position: BoardNodePosition) => {
      if (!channel) return;
      const now = Date.now();
      if (now - lastSentRef.current < 50) return;
      lastSentRef.current = now;
      channel.push("cursor_move", { x: position.x, y: position.y });
    },
    [channel],
  );

  return { participants, cursors, typingUsers, sendCursorPosition };
}
