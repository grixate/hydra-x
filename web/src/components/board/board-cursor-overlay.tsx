import type { BoardNodePosition, BoardPresenceUser } from "@/types";

type BoardCursorOverlayProps = {
  cursors: Map<string, BoardNodePosition>;
  participants: BoardPresenceUser[];
  typingUsers: Set<string>;
};

export function BoardCursorOverlay({ cursors, participants, typingUsers }: BoardCursorOverlayProps) {
  const participantMap = new Map(participants.map((p) => [p.user_id, p]));

  return (
    <svg className="pointer-events-none absolute inset-0 z-50 overflow-visible">
      {Array.from(cursors.entries()).map(([userId, pos]) => {
        const participant = participantMap.get(userId);
        if (!participant) return null;
        const isTyping = typingUsers.has(userId);

        return (
          <g key={userId} transform={`translate(${pos.x}, ${pos.y})`}>
            {/* Cursor arrow */}
            <path
              d="M0 0 L0 14 L4 10 L8 16 L10 15 L6 9 L12 9 Z"
              fill={participant.color}
              stroke="black"
              strokeWidth={0.5}
            />
            {/* Name label */}
            <rect
              x={14}
              y={8}
              width={participant.name.length * 7 + (isTyping ? 24 : 8)}
              height={16}
              rx={4}
              fill={participant.color}
              opacity={0.9}
            />
            <text x={18} y={20} fontSize={10} fill="white" fontFamily="monospace">
              {participant.name}
              {isTyping ? " •••" : ""}
            </text>
          </g>
        );
      })}
    </svg>
  );
}
