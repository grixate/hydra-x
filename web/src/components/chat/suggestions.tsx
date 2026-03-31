import type { GraphDataNode } from "@/types";

interface ChatSuggestionsProps {
  selectedNodes: GraphDataNode[];
  onSelect: (suggestion: string) => void;
  defaultSuggestions?: string[];
}

function getSuggestions(nodes: GraphDataNode[], defaults?: string[]): string[] {
  if (nodes.length === 0) {
    return defaults ?? [
      "What should I work on next?",
      "Show me contradictions",
      "Summarize recent decisions",
    ];
  }
  if (nodes.length === 1) {
    const node = nodes[0];
    const base = ["What depends on this?", "Show all connections"];
    if (node.node_type === "decision")
      return [...base, "Evidence strength?", "Is this still valid?"];
    if (node.node_type === "insight")
      return [...base, "How strong is this evidence?", "What decisions use this?"];
    if (node.node_type === "task")
      return [...base, "Why does this exist?", "What's blocking this?"];
    if (node.node_type === "requirement")
      return [...base, "Is this well-evidenced?", "What tasks implement this?"];
    return base;
  }
  return [
    "How are these connected?",
    "Do these contradict?",
    "Compare evidence strength",
    "What's the gap between these?",
  ];
}

export function ChatSuggestions({
  selectedNodes,
  onSelect,
  defaultSuggestions,
}: ChatSuggestionsProps) {
  const suggestions = getSuggestions(selectedNodes, defaultSuggestions);

  return (
    <div className="flex gap-1.5 overflow-x-auto px-4 py-2">
      {suggestions.map((s) => (
        <button
          key={s}
          type="button"
          onClick={() => onSelect(s)}
          className="shrink-0 rounded-full border bg-background/80 px-3 py-1 text-[11px] text-muted-foreground transition-colors hover:bg-muted hover:text-foreground"
        >
          {s}
        </button>
      ))}
    </div>
  );
}
