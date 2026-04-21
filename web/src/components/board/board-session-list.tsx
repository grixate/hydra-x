import { useState, useEffect } from "react";
import { useNavigate } from "react-router-dom";
import { motion } from "motion/react";
import { Plus } from "lucide-react";
import { api } from "@/lib/api";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { NODE_COLORS } from "@/components/graph/graph-constants";
import { nodeTypeLabel } from "@/components/shared/node-type-icon";
import { AGENT_ICONS } from "./board-constants";
import { relativeLabel } from "@/lib/utils";
import type { BoardSession } from "@/types";

type BoardSessionListProps = {
  projectId: number;
};

export function BoardSessionList({ projectId }: BoardSessionListProps) {
  const navigate = useNavigate();
  const [sessions, setSessions] = useState<BoardSession[]>([]);
  const [loading, setLoading] = useState(true);
  const [creating, setCreating] = useState(false);



  useEffect(() => {
    api.listBoardSessions(projectId)
      .then(setSessions)
      .catch(() => {})
      .finally(() => setLoading(false));
  }, [projectId]);

  const activeSessions = sessions.filter((s) => s.status === "active");
  const archivedSessions = sessions.filter((s) => s.status === "completed" || s.status === "archived");

  async function createAndNavigate() {
    if (creating) return;
    setCreating(true);
    try {
      const session = await api.createBoardSession(projectId, { title: "Untitled session" });
      navigate(`/projects/${projectId}/board/${session.id}`);
    } catch {
      setCreating(false);
    }
  }

  if (loading) {
    return (
      <div className="mx-auto max-w-2xl px-4 py-8">
        <div className="space-y-3">
          {[1, 2, 3].map((i) => (
            <div key={i} className="h-28 animate-pulse rounded-xl bg-muted/50" />
          ))}
        </div>
      </div>
    );
  }

  const introCard = (
    <motion.div
      initial={{ opacity: 0, y: -8 }}
      animate={{ opacity: 1, y: 0 }}
      exit={{ opacity: 0, y: -8 }}
      className="rounded-xl border bg-muted/30 p-5 mb-6"
    >
      <p className="text-sm font-medium mb-2">About Board sessions</p>
      <p className="text-sm text-muted-foreground leading-relaxed">
        Boards are collaborative workspaces where you explore ideas with AI agents.
        Upload documents, take notes, and let agents analyze your materials into
        structured insights and decisions.
      </p>
      <p className="text-sm text-muted-foreground leading-relaxed mt-2">
        Everything on a board is a draft — nothing enters your permanent product graph
        until you push it.
      </p>
      <p className="text-sm text-muted-foreground leading-relaxed mt-2">
        Best for 1-5 files per session. For larger imports (10+ documents), use bulk
        import from the + menu.
      </p>
    </motion.div>
  );

  if (sessions.length === 0) {
    return (
      <div className="mx-auto max-w-2xl px-4 py-8">
        {introCard}
        <div className="flex h-[60vh] items-center justify-center">
          <div className="text-center">
            <p className="text-base font-medium">Start a session</p>
            <p className="mt-1.5 text-sm text-muted-foreground leading-relaxed">
              Board sessions are where you explore ideas,<br />
              brainstorm with agents, and work on problems together.
            </p>
            <Button
              variant="outline"
              className="mt-5"
              onClick={createAndNavigate}
              disabled={creating}
            >
              <Plus className="mr-2 h-4 w-4" />
              {creating ? "Creating..." : "New session"}
            </Button>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="mx-auto max-w-2xl px-4 py-8">
      {introCard}

      {/* Active sessions */}
      {activeSessions.length > 0 && (
        <section>
          <div className="flex items-center gap-2 pb-3 pt-2">
            <h3 className="text-xs font-semibold uppercase tracking-widest text-muted-foreground">
              Active
            </h3>
            <Badge variant="secondary" className="text-[10px]">
              {activeSessions.length}
            </Badge>
          </div>

          <div className="space-y-3">
            {activeSessions.map((session, i) => (
              <motion.button
                key={session.id}
                initial={{ opacity: 0, y: 16 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ duration: 0.35, delay: i * 0.08, ease: [0.25, 0.46, 0.45, 0.94] }}
                onClick={() => navigate(`/projects/${projectId}/board/${session.id}`)}
                className="w-full rounded-xl border bg-card p-5 text-left transition-colors hover:bg-accent/50"
              >
                <h3 className="text-base font-medium leading-snug">
                  {session.title}
                </h3>

                {session.description && (
                  <p className="mt-1.5 text-sm text-muted-foreground line-clamp-2 leading-relaxed">
                    {session.description}
                  </p>
                )}

                {/* Progress + node type dots */}
                <div className="mt-3 flex items-center gap-3">
                  <span className="text-xs text-muted-foreground">
                    {session.draft_node_count} draft
                  </span>
                  <span className="text-xs text-muted-foreground">·</span>
                  <span className="text-xs text-muted-foreground">
                    {session.promoted_node_count} pushed
                  </span>

                  {session.node_types && session.node_types.length > 0 && (
                    <>
                      <span className="text-xs text-muted-foreground">·</span>
                      <div className="flex items-center gap-1">
                        {session.node_types.map((type) => (
                          <div
                            key={type}
                            className="h-2 w-2 rounded-full"
                            style={{ backgroundColor: NODE_COLORS[type] ?? NODE_COLORS.default }}
                            title={nodeTypeLabel(type)}
                          />
                        ))}
                      </div>
                    </>
                  )}
                </div>

                {/* Agents + time */}
                <div className="mt-2 flex items-center gap-2 text-xs text-muted-foreground">
                  {session.active_agents?.map((agent) => (
                    <span key={agent} title={agent}>
                      {AGENT_ICONS[agent] ?? "🤖"}
                    </span>
                  ))}

                  <span className="ml-auto">
                    {session.updated_at ? relativeLabel(session.updated_at) : ""}
                  </span>
                </div>
              </motion.button>
            ))}

            {/* New session dashed card */}
            <motion.button
              initial={{ opacity: 0, y: 16 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.35, delay: activeSessions.length * 0.08, ease: [0.25, 0.46, 0.45, 0.94] }}
              onClick={createAndNavigate}
              disabled={creating}
              className="w-full rounded-xl border-2 border-dashed border-muted-foreground/20 p-5 text-center transition-colors hover:border-muted-foreground/40 hover:bg-muted/30"
            >
              <Plus className="mx-auto h-5 w-5 text-muted-foreground/50" />
              <p className="mt-2 text-sm text-muted-foreground">
                {creating ? "Creating..." : "New session"}
              </p>
            </motion.button>
          </div>
        </section>
      )}

      {/* If only archived sessions exist, show new session button at top */}
      {activeSessions.length === 0 && archivedSessions.length > 0 && (
        <div className="pb-4 pt-2">
          <Button variant="outline" onClick={createAndNavigate} disabled={creating}>
            <Plus className="mr-2 h-4 w-4" />
            {creating ? "Creating..." : "New session"}
          </Button>
        </div>
      )}

      {/* Archived sessions */}
      {archivedSessions.length > 0 && (
        <section>
          <div className="flex items-center gap-2 pb-3 pt-6">
            <h3 className="text-xs font-semibold uppercase tracking-widest text-muted-foreground">
              Archived
            </h3>
            <Badge variant="secondary" className="text-[10px]">
              {archivedSessions.length}
            </Badge>
          </div>

          <div className="space-y-0.5">
            {archivedSessions.map((session, i) => (
              <motion.button
                key={session.id}
                initial={{ opacity: 0, x: -8 }}
                animate={{ opacity: 1, x: 0 }}
                transition={{ duration: 0.25, delay: i * 0.03 }}
                onClick={() => navigate(`/projects/${projectId}/board/${session.id}`)}
                className="flex w-full items-center gap-3 rounded-md px-2 py-2 text-left transition-colors hover:bg-muted/50"
              >
                <div className="h-2 w-2 shrink-0 rounded-full bg-muted-foreground/30" />
                <span className="flex-1 truncate text-sm text-muted-foreground">
                  {session.title}
                </span>
                <span className="shrink-0 text-xs text-muted-foreground">
                  {session.promoted_node_count} pushed
                </span>
                <span className="shrink-0 text-xs text-muted-foreground">
                  {session.updated_at ? relativeLabel(session.updated_at) : ""}
                </span>
              </motion.button>
            ))}
          </div>
        </section>
      )}
    </div>
  );
}
