import { AGENT_ICONS } from "./board-constants";

type BoardEmptyStateProps = {
  onSuggestion: (text: string) => void;
};

const suggestions = [
  "Explore a new feature idea",
  "Analyze a competitor",
  "Plan the next sprint",
];

export function BoardEmptyState({ onSuggestion }: BoardEmptyStateProps) {
  const agents = Object.entries(AGENT_ICONS);

  return (
    <div className="absolute inset-0 flex items-center justify-center pointer-events-none z-10">
      <div className="flex flex-col items-center gap-8 pointer-events-auto">
        {/* Campfire: agent avatars in a circle */}
        <div className="relative w-56 h-56">
          {agents.map(([slug, icon], i) => {
            const angle = (i / agents.length) * Math.PI * 2 - Math.PI / 2;
            const x = 50 + Math.cos(angle) * 40;
            const y = 50 + Math.sin(angle) * 40;
            return (
              <div
                key={slug}
                className="absolute flex flex-col items-center gap-1"
                style={{
                  left: `${x}%`,
                  top: `${y}%`,
                  transform: "translate(-50%, -50%)",
                }}
              >
                <span className="text-2xl opacity-40">{icon}</span>
                <span className="text-[9px] text-zinc-600 capitalize">{slug.replace("_", " ")}</span>
              </div>
            );
          })}
          {/* Center label */}
          <div className="absolute inset-0 flex items-center justify-center">
            <span className="text-2xl opacity-20">👤</span>
          </div>
        </div>

        <div className="text-center">
          <h2 className="text-lg font-medium text-zinc-300">What should we explore?</h2>
          <p className="mt-1 text-xs text-zinc-600">Start a conversation with an agent or add a node</p>
        </div>

        {/* Suggestion chips */}
        <div className="flex gap-2">
          {suggestions.map((s) => (
            <button
              key={s}
              onClick={() => onSuggestion(s)}
              className="rounded-xl border border-zinc-800 bg-zinc-900/50 px-4 py-2 text-xs text-zinc-400 hover:border-zinc-600 hover:text-white transition"
            >
              {s}
            </button>
          ))}
        </div>
      </div>
    </div>
  );
}
