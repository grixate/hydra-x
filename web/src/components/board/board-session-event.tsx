import type { BoardSessionEvent } from "@/types";
import { NODE_COLORS } from "@/components/graph/graph-constants";
import { relativeLabel } from "@/lib/utils";

interface SessionEventProps {
  event: BoardSessionEvent;
  onNodeClick?: (nodeType: string, nodeId: number) => void;
}

const EVENT_ICONS: Record<string, string> = {
  source_uploaded: "📄",
  note_added: "📝",
  url_added: "🔗",
  node_created: "●",
  node_promoted: "↗",
  node_discarded: "×",
  node_removed: "×",
  member_joined: "👤",
  member_left: "👤",
  session_renamed: "✎",
};

const EVENT_ACTIONS: Record<string, string> = {
  source_uploaded: "uploaded",
  note_added: "added a note:",
  url_added: "added link:",
  node_created: "created",
  node_promoted: "pushed to graph:",
  node_discarded: "discarded",
  node_removed: "removed",
  member_joined: "joined this session",
  member_left: "left this session",
  session_renamed: "renamed session to:",
};

export function SessionEvent({ event, onNodeClick }: SessionEventProps) {
  const icon = EVENT_ICONS[event.event_type] ?? "•";
  const action = EVENT_ACTIONS[event.event_type] ?? event.event_type;
  const isPromotion = event.event_type === "node_promoted";

  // For node_created, use colored dot
  const dotColor =
    event.event_type === "node_created" && event.target_type
      ? NODE_COLORS[event.target_type] ?? NODE_COLORS.default
      : undefined;

  return (
    <div className="flex items-start gap-2 px-4 py-1.5">
      <span className="mt-0.5 shrink-0 text-xs">
        {dotColor ? (
          <span
            className="inline-block h-2 w-2 rounded-full mt-0.5"
            style={{ backgroundColor: dotColor }}
          />
        ) : (
          <span className={isPromotion ? "text-primary" : ""}>{icon}</span>
        )}
      </span>
      <p className="text-xs text-muted-foreground leading-relaxed flex-1">
        <span className="font-medium text-foreground/70">
          {event.actor_name === "operator" ? "You" : event.actor_name}
        </span>
        {" "}{action}{" "}
        {event.target_title && (
          <button
            className="font-medium text-foreground/70 hover:underline"
            onClick={() => {
              if (event.target_type && event.target_id) {
                onNodeClick?.(event.target_type, event.target_id);
              }
            }}
          >
            {event.target_title}
          </button>
        )}
      </p>
      <span className="ml-auto shrink-0 text-[10px] text-muted-foreground/50">
        {relativeLabel(event.inserted_at)}
      </span>
    </div>
  );
}

// Grouped event display
interface GroupedSessionEventProps {
  events: BoardSessionEvent[];
  onNodeClick?: (nodeType: string, nodeId: number) => void;
}

export function GroupedSessionEvent({ events, onNodeClick }: GroupedSessionEventProps) {
  const first = events[0];
  const action = EVENT_ACTIONS[first.event_type] ?? first.event_type;
  const dotColor =
    first.event_type === "node_created" && first.target_type
      ? NODE_COLORS[first.target_type] ?? NODE_COLORS.default
      : undefined;

  return (
    <div className="px-4 py-1.5">
      <div className="flex items-start gap-2">
        <span className="mt-0.5 shrink-0 text-xs">
          {dotColor ? (
            <span
              className="inline-block h-2 w-2 rounded-full mt-0.5"
              style={{ backgroundColor: dotColor }}
            />
          ) : (
            EVENT_ICONS[first.event_type] ?? "•"
          )}
        </span>
        <div className="flex-1">
          <p className="text-xs text-muted-foreground">
            <span className="font-medium text-foreground/70">
              {first.actor_name === "operator" ? "You" : first.actor_name}
            </span>
            {" "}{action}{" "}{events.length} {first.target_type ? `${first.target_type}${events.length > 1 ? "s" : ""}` : "items"}:
          </p>
          <ul className="mt-0.5 space-y-0">
            {events.map((e) => (
              <li key={e.id} className="text-xs text-muted-foreground pl-1">
                <span className="text-muted-foreground/50">·</span>{" "}
                {e.target_title && (
                  <button
                    className="hover:underline"
                    onClick={() => {
                      if (e.target_type && e.target_id) onNodeClick?.(e.target_type, e.target_id);
                    }}
                  >
                    {e.target_title}
                  </button>
                )}
              </li>
            ))}
          </ul>
        </div>
        <span className="ml-auto shrink-0 text-[10px] text-muted-foreground/50">
          {relativeLabel(first.inserted_at)}
        </span>
      </div>
    </div>
  );
}

// Group consecutive events of same type/actor within 60s
export function groupConsecutiveEvents(
  events: BoardSessionEvent[],
): Array<{ type: "single"; event: BoardSessionEvent } | { type: "group"; events: BoardSessionEvent[] }> {
  const result: Array<{ type: "single"; event: BoardSessionEvent } | { type: "group"; events: BoardSessionEvent[] }> = [];
  let currentGroup: BoardSessionEvent[] = [];

  for (const event of events) {
    const last = currentGroup[currentGroup.length - 1];
    if (
      last &&
      event.event_type === last.event_type &&
      event.actor_name === last.actor_name &&
      Math.abs(new Date(event.inserted_at).getTime() - new Date(last.inserted_at).getTime()) < 60000
    ) {
      currentGroup.push(event);
    } else {
      if (currentGroup.length > 1) {
        result.push({ type: "group", events: currentGroup });
      } else if (currentGroup.length === 1) {
        result.push({ type: "single", event: currentGroup[0] });
      }
      currentGroup = [event];
    }
  }
  if (currentGroup.length > 1) {
    result.push({ type: "group", events: currentGroup });
  } else if (currentGroup.length === 1) {
    result.push({ type: "single", event: currentGroup[0] });
  }

  return result;
}
