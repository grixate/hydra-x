import { useState, useEffect } from "react";
import { useNavigate } from "react-router-dom";
import { MoreHorizontal } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { api } from "@/lib/api";
import type { BoardSession, BoardPresenceUser } from "@/types";

type BoardSessionHeaderProps = {
  projectId: number;
  session: BoardSession;
  participants: BoardPresenceUser[];
  draftCount: number;
  onSessionUpdate: (session: BoardSession) => void;
  onPushToGraph: () => void;
};

export function BoardSessionHeader({
  projectId,
  session,
  participants,
  draftCount,
  onSessionUpdate,
  onPushToGraph,
}: BoardSessionHeaderProps) {
  const navigate = useNavigate();
  const [editing, setEditing] = useState(false);
  const [title, setTitle] = useState(session.title);

  useEffect(() => {
    setTitle(session.title);
  }, [session.title]);

  async function saveTitle() {
    setEditing(false);
    if (title.trim() && title !== session.title) {
      const updated = await api.updateBoardSession(projectId, session.id, { title: title.trim() });
      onSessionUpdate(updated);
    }
  }

  async function archiveSession() {
    const updated = await api.updateBoardSession(projectId, session.id, { status: "archived" });
    onSessionUpdate(updated);
    navigate(`/projects/${projectId}/board`);
  }

  return (
    <div className="flex items-center justify-between px-4 h-[45px] border-b shrink-0">
      {/* Left: back + title */}
      <div className="flex items-center gap-3">
        <Button
          variant="ghost"
          size="sm"
          onClick={() => navigate(`/projects/${projectId}/board`)}
        >
          ← Sessions
        </Button>

        {editing ? (
          <input
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            onBlur={saveTitle}
            onKeyDown={(e) => e.key === "Enter" && saveTitle()}
            autoFocus
            className="bg-transparent text-sm font-medium outline-none border-none p-0 min-w-[80px]"
            style={{ width: `${Math.max(title.length, 8)}ch` }}
          />
        ) : (
          <button
            onClick={() => setEditing(true)}
            className="text-sm font-medium hover:underline"
          >
            {session.title}
          </button>
        )}
      </div>

      {/* Right: participants + actions */}
      <div className="flex items-center gap-3">
        {/* Participant avatars */}
        <div className="flex -space-x-1.5">
          {participants.slice(0, 5).map((p) => (
            <div
              key={p.user_id}
              className="flex h-6 w-6 items-center justify-center rounded-full border border-background bg-muted text-[10px] font-medium"
              title={p.name}
            >
              {p.name.charAt(0).toUpperCase()}
            </div>
          ))}
          {participants.length > 5 && (
            <div className="flex h-6 w-6 items-center justify-center rounded-full border border-background bg-muted text-[10px] text-muted-foreground">
              +{participants.length - 5}
            </div>
          )}
        </div>

        <Button variant="outline" size="sm">
          Invite
        </Button>

        {/* Push to graph */}
        {draftCount > 0 && (
          <Button size="sm" onClick={onPushToGraph}>
            Push to graph ({draftCount})
          </Button>
        )}

        {/* More menu */}
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button variant="ghost" size="icon-sm">
              <MoreHorizontal className="h-4 w-4" />
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end">
            <DropdownMenuItem onClick={() => setEditing(true)}>
              Rename
            </DropdownMenuItem>
            <DropdownMenuItem onClick={archiveSession}>
              Archive session
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </div>
    </div>
  );
}
