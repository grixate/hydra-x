import { useState, useEffect } from "react";
import { useNavigate } from "react-router-dom";
import { api } from "@/lib/api";
import type { BoardSession } from "@/types";

type BoardSessionListProps = {
  projectId: number;
};

export function BoardSessionList({ projectId }: BoardSessionListProps) {
  const navigate = useNavigate();
  const [sessions, setSessions] = useState<BoardSession[]>([]);
  const [loading, setLoading] = useState(true);
  const [showNew, setShowNew] = useState(false);
  const [newTitle, setNewTitle] = useState("");

  useEffect(() => {
    api.listBoardSessions(projectId)
      .then((data) => {
        setSessions(data);
      })
      .catch(() => {
        // Silently handle — sessions will just be empty
      })
      .finally(() => setLoading(false));
  }, [projectId]);

  const activeSessions = sessions.filter((s) => s.status === "active");
  const completedSessions = sessions.filter((s) => s.status === "completed" || s.status === "archived");

  async function createSession() {
    if (!newTitle.trim()) return;
    try {
      const session = await api.createBoardSession(projectId, { title: newTitle.trim() });
      navigate(`/projects/${projectId}/board/${session.id}`);
    } catch {
      // Could show a toast here; for now just keep the form open
    }
  }

  function relativeTime(dateStr?: string) {
    if (!dateStr) return "";
    const diff = (Date.now() - new Date(dateStr).getTime()) / 1000;
    if (diff < 60) return "just now";
    if (diff < 3600) return `${Math.floor(diff / 60)}m ago`;
    if (diff < 86400) return `${Math.floor(diff / 3600)}h ago`;
    return `${Math.floor(diff / 86400)}d ago`;
  }

  if (loading) {
    return <div className="flex items-center justify-center py-20 text-zinc-600">Loading sessions...</div>;
  }

  return (
    <div className="mx-auto max-w-2xl space-y-8 py-8">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-medium text-white">Board</h1>
        <button
          onClick={() => setShowNew(true)}
          className="rounded-xl border border-zinc-700 bg-zinc-800 px-4 py-2 text-xs uppercase tracking-wider text-zinc-400 hover:bg-zinc-700 hover:text-white transition"
        >
          + New session
        </button>
      </div>

      {/* New session form */}
      {showNew && (
        <div className="rounded-xl border border-zinc-800 bg-zinc-900/80 p-4">
          <div className="flex gap-3">
            <input
              value={newTitle}
              onChange={(e) => setNewTitle(e.target.value)}
              onKeyDown={(e) => e.key === "Enter" && createSession()}
              placeholder="What do you want to explore?"
              autoFocus
              className="flex-1 rounded-lg border border-zinc-700 bg-zinc-800 px-4 py-2 text-sm text-white placeholder-zinc-600 focus:border-orange-500 focus:outline-none"
            />
            <button
              onClick={createSession}
              className="rounded-lg bg-orange-600 px-6 py-2 text-xs font-medium uppercase text-white hover:bg-orange-500 transition"
            >
              Create
            </button>
            <button
              onClick={() => setShowNew(false)}
              className="rounded-lg border border-zinc-700 px-3 py-2 text-xs text-zinc-500 hover:text-white transition"
            >
              Cancel
            </button>
          </div>
        </div>
      )}

      {/* Active sessions */}
      {activeSessions.length > 0 && (
        <section>
          <h2 className="mb-3 text-[10px] uppercase tracking-[0.2em] text-zinc-500">Active sessions</h2>
          <div className="space-y-3">
            {activeSessions.map((session) => (
              <button
                key={session.id}
                onClick={() => navigate(`/projects/${projectId}/board/${session.id}`)}
                className="w-full rounded-xl border border-zinc-800 bg-zinc-900/60 px-5 py-4 text-left hover:border-zinc-700 hover:bg-zinc-900 transition"
              >
                <h3 className="text-base font-medium text-white">{session.title}</h3>
                {session.description && (
                  <p className="mt-1 text-xs text-zinc-500 line-clamp-1">{session.description}</p>
                )}
                <div className="mt-2 flex gap-4 text-[10px] text-zinc-600">
                  <span>{session.draft_node_count} draft nodes</span>
                  <span>{session.promoted_node_count} promoted</span>
                  <span>Last active: {relativeTime(session.updated_at)}</span>
                </div>
              </button>
            ))}
          </div>
        </section>
      )}

      {/* Completed sessions */}
      {completedSessions.length > 0 && (
        <section>
          <h2 className="mb-3 text-[10px] uppercase tracking-[0.2em] text-zinc-500">Completed</h2>
          <div className="space-y-3">
            {completedSessions.map((session) => (
              <button
                key={session.id}
                onClick={() => navigate(`/projects/${projectId}/board/${session.id}`)}
                className="w-full rounded-xl border border-zinc-800 bg-zinc-900/40 px-5 py-4 text-left hover:border-zinc-700 transition opacity-70"
              >
                <div className="flex items-center justify-between">
                  <h3 className="text-sm text-zinc-300">{session.title}</h3>
                  <span className="text-[10px] text-green-500">✓ done</span>
                </div>
                <div className="mt-1 text-[10px] text-zinc-600">
                  {session.promoted_node_count} nodes promoted
                </div>
              </button>
            ))}
          </div>
        </section>
      )}

      {sessions.length === 0 && !showNew && (
        <div className="py-20 text-center">
          <p className="text-zinc-600">No board sessions yet.</p>
          <button
            onClick={() => setShowNew(true)}
            className="mt-4 rounded-xl border border-dashed border-zinc-700 px-6 py-3 text-xs text-zinc-500 hover:border-zinc-500 hover:text-white transition"
          >
            + Create your first session
          </button>
        </div>
      )}
    </div>
  );
}
