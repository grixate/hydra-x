import { parseMessageContent, type ContentSegment } from "./board-content-parser";
import { BoardInlineNodeCard } from "./board-inline-node-card";
import { BoardInlineTrail } from "./board-inline-trail";
import { BoardInlineArtifact } from "./board-inline-artifact";
import { cn } from "@/lib/utils";

type BoardChatMessageProps = {
  role: string;
  content: string;
  agent?: string;
  projectId: number;
  onSelectContext?: (nodeType: string, nodeId: number) => void;
};

export function BoardChatMessage({
  role,
  content,
  agent,
  projectId,
  onSelectContext,
}: BoardChatMessageProps) {
  const isUser = role === "user";

  if (isUser) {
    return (
      <div className="flex justify-end">
        <div className="max-w-[85%] rounded-2xl bg-foreground text-background px-5 py-3.5 text-sm leading-relaxed">
          {content}
        </div>
      </div>
    );
  }

  // Agent message — parse for structured content
  const segments = parseMessageContent(content);
  const hasStructured = segments.some((s) => s.type !== "text");

  return (
    <div className="flex justify-start">
      <div className={cn("max-w-[85%] rounded-2xl px-5 py-3.5", hasStructured ? "" : "bg-muted/60")}>
        <div className="mb-1.5 text-[10px] font-semibold uppercase tracking-widest text-muted-foreground">
          {agent ?? "Agent"}
        </div>
        <div className="text-sm leading-relaxed">
          {segments.map((segment, i) => (
            <MessageSegment
              key={i}
              segment={segment}
              projectId={projectId}
              onSelectContext={onSelectContext}
            />
          ))}
        </div>
      </div>
    </div>
  );
}

function MessageSegment({
  segment,
  projectId,
  onSelectContext,
}: {
  segment: ContentSegment;
  projectId: number;
  onSelectContext?: (nodeType: string, nodeId: number) => void;
}) {
  switch (segment.type) {
    case "text":
      return <span className="whitespace-pre-wrap">{segment.content}</span>;

    case "node":
      return (
        <BoardInlineNodeCard
          projectId={projectId}
          nodeType={segment.nodeType}
          nodeId={segment.nodeId}
          onSelectContext={onSelectContext}
        />
      );

    case "trail":
      return (
        <BoardInlineTrail
          projectId={projectId}
          nodeType={segment.nodeType}
          nodeId={segment.nodeId}
        />
      );

    case "artifact":
      return (
        <BoardInlineArtifact
          projectId={projectId}
          artifactId={segment.artifactId}
        />
      );

    default:
      return null;
  }
}
