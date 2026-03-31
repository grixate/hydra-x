import { useParams } from "react-router-dom";
import { BoardSessionList } from "@/components/board/board-session-list";
import { BoardWorkspace } from "@/components/board/board-workspace";

export function BoardPage() {
  const { projectId, sessionId } = useParams<{ projectId: string; sessionId?: string }>();
  const pid = Number(projectId);

  if (sessionId) {
    const sid = Number(sessionId);
    if (Number.isNaN(sid)) {
      return <BoardSessionList projectId={pid} />;
    }
    return <BoardWorkspace projectId={pid} sessionId={sid} />;
  }

  return <BoardSessionList projectId={pid} />;
}
