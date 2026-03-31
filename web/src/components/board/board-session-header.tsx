import { useState, useEffect } from "react";
import { useNavigate } from "react-router-dom";
import { api } from "@/lib/api";
import type { BoardSession, BoardPresenceUser } from "@/types";
import { PRESENCE_COLORS } from "./board-constants";

type BoardSessionHeaderProps = {
  projectId: number;
  session: BoardSession;
  participants: BoardPresenceUser[];
  draftCount: number;
  onSessionUpdate: (session: BoardSession) => void;
  onPromoteAll: () => void;
};

export function BoardSessionHeader({
  projectId,
  session,
  participants,
  draftCount,
  onSessionUpdate,
  onPromoteAll,
}: BoardSessionHeaderProps) {
  const navigate = useNavigate();
  const [editing, setEditing] = useState(false);
  const [title, setTitle] = useState(session.title);

  // Sync local title when session prop changes (e.g. from remote update)
  useEffect(() => {
    setTitle(session.title);
  }, [session.title]);

  async function saveTitle() {
    setEditing(false);
    if (title !== session.title) {
      const updated = await api.updateBoardSession(projectId, session.id, { title });
      onSessionUpdate(updated);
    }
  }

  async function completeSession() {
    const updated = await api.updateBoardSession(projectId, session.id, { status: "completed" });
    onSessionUpdate(updated);
    navigate(`/projects/${projectId}/board`);
  }

  return (
    <div className="flex h-12 items-center justify-between border-b border-zinc-800 bg-zinc-950/80 px-4 backdrop-blur-sm">
      <div className="flex items-center gap-3">
        <button
          onClick={() => navigate(`/projects/${projectId}/board`)}
          className="text-xs text-zinc-500 hover:text-white transition"
        >
          ← Board
        </button>
        <span className="text-zinc-700">|</span>
        {editing ? (
          <input
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            onBlur={saveTitle}
            onKeyDown={(e) => e.key === "Enter" && saveTitle()}
            autoFocus
            className="bg-transparent text-sm font-medium text-white border-b border-zinc-600 outline-none px-1"
          />
        ) : (
          <button
            onClick={() => setEditing(true)}
            className="text-sm font-medium text-white hover:text-zinc-300 transition"
          >
            {session.title}
          </button>
        )}
      </div>

      <div className="flex items-center gap-4">
        {/* Participants */}
        <div className="flex -space-x-2">
          {participants.slice(0, 5).map((p, i) => (
            <div
              key={p.user_id}
              className="flex h-6 w-6 items-center justify-center rounded-full border border-zinc-800 text-[10px] font-bold text-white"
              style={{ backgroundColor: PRESENCE_COLORS[i % PRESENCE_COLORS.length] }}
              title={p.name}
            >
              {p.name.charAt(0).toUpperCase()}
            </div>
          ))}
          {participants.length > 5 && (
            <div className="flex h-6 w-6 items-center justify-center rounded-full border border-zinc-800 bg-zinc-700 text-[10px] text-zinc-300">
              +{participants.length - 5}
            </div>
          )}
        </div>

        {/* Actions */}
        {session.status === "active" && draftCount > 0 && (
          <button
            onClick={onPromoteAll}
            className="rounded-lg border border-green-500/30 bg-green-500/10 px-3 py-1 text-[10px] uppercase tracking-wider text-green-400 hover:bg-green-500/20 transition"
          >
            Promote all ({draftCount})
          </button>
        )}
        {session.status === "active" && (
          <button
            onClick={completeSession}
            className="rounded-lg border border-zinc-700 bg-zinc-800 px-3 py-1 text-[10px] uppercase tracking-wider text-zinc-400 hover:bg-zinc-700 hover:text-white transition"
          >
            Complete ✓
          </button>
        )}
      </div>
    </div>
  );
}
