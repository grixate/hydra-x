import { useState, useCallback, useRef, useEffect } from "react";
import { Button } from "@/components/ui/button";
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover";
import { ArrowUp, ChevronDown, Brain, Search, Compass, Paintbrush, Database } from "lucide-react";
import type { GraphDataNode } from "@/types";
import { ChatContextBar } from "./context-bar";
import { ChatSuggestions } from "./suggestions";
import { UniversalActionMenu } from "./universal-action-menu";

export const AGENTS = [
  { slug: "memory", label: "Memory", icon: Database },
  { slug: "researcher", label: "Researcher", icon: Search },
  { slug: "strategist", label: "Strategist", icon: Compass },
  { slug: "architect", label: "Architect", icon: Brain },
  { slug: "designer", label: "Designer", icon: Paintbrush },
] as const;

export type Surface = "stream" | "graph" | "board" | "onboarding";

const BOARD_PLACEHOLDERS = [
  "Drop files above or type here to start...",
  "Try: 'Analyze our pricing strategy'",
  "Try: 'What should we focus on first?'",
  "Try: 'Compare options for authentication'",
];

const SURFACE_DEFAULTS: Record<Surface, { agent: string; placeholder: string; suggestions: string[] }> = {
  stream: {
    agent: "memory",
    placeholder: "What's happening with the product?",
    suggestions: ["What should I focus on today?", "Summarize this week", "Any contradictions?"],
  },
  graph: {
    agent: "memory",
    placeholder: "Ask the graph...",
    suggestions: ["What should I work on next?", "Show me contradictions", "Summarize recent decisions"],
  },
  board: {
    agent: "strategist",
    placeholder: "Manage tasks, ask about priorities...",
    suggestions: ["What's blocked?", "Prioritize my backlog", "Create a task for..."],
  },
  onboarding: {
    agent: "strategist",
    placeholder: "Tell us about your product...",
    suggestions: [],
  },
};

interface UniversalInputProps {
  surface: Surface;
  projectId?: number;
  onSubmit: (message: string, agent: string, contextNodeIds: string[]) => void;
  currentAgent?: string;
  onAgentChange?: (agent: string) => void;
  selectedNodes?: GraphDataNode[];
  previewNode?: GraphDataNode | null;
  onClearSelection?: () => void;
  onRemoveNode?: (nodeId: string) => void;
  initialValue?: string;
}

export function UniversalInput({
  surface,
  projectId,
  onSubmit,
  currentAgent,
  onAgentChange,
  selectedNodes = [],
  previewNode,
  onClearSelection,
  onRemoveNode,
  initialValue,
}: UniversalInputProps) {
  const defaults = SURFACE_DEFAULTS[surface];
  const agent = currentAgent ?? defaults.agent;

  const [input, setInput] = useState(initialValue ?? "");

  // Parent-driven prefill (e.g., onboarding chip "I'm building a product for…")
  useEffect(() => {
    if (initialValue !== undefined) {
      setInput(initialValue);
      // Focus the textarea so the user can continue typing.
      queueMicrotask(() => textareaRef.current?.focus());
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [initialValue]);
  const [agentOpen, setAgentOpen] = useState(false);
  const [isFocused, setIsFocused] = useState(false);
  const [rotatingIndex, setRotatingIndex] = useState(0);
  const textareaRef = useRef<HTMLTextAreaElement>(null);

  const activeAgent = AGENTS.find((a) => a.slug === agent) ?? AGENTS[0];

  useEffect(() => {
    const el = textareaRef.current;
    if (!el) return;
    el.style.height = "auto";
    el.style.height = Math.min(el.scrollHeight, 160) + "px";
  }, [input]);

  const handleSubmit = useCallback(() => {
    const text = input.trim();
    if (!text) return;
    onSubmit(text, agent, selectedNodes.map((n) => n.id));
    setInput("");
  }, [input, agent, selectedNodes, onSubmit]);

  const handleSuggestion = useCallback(
    (suggestion: string) => {
      onSubmit(suggestion, agent, selectedNodes.map((n) => n.id));
    },
    [agent, selectedNodes, onSubmit],
  );

  const hasText = input.trim().length > 0;
  const hasContext = selectedNodes.length > 0;
  const hasPreview = !!previewNode && !selectedNodes.some((n) => n.id === previewNode.id);
  const showContextBar = hasContext || hasPreview;

  // Rotating placeholders for board surface
  useEffect(() => {
    if (surface !== "board" || isFocused || hasText) return;
    const interval = setInterval(() => {
      setRotatingIndex((i) => (i + 1) % BOARD_PLACEHOLDERS.length);
    }, 4000);
    return () => clearInterval(interval);
  }, [surface, isFocused, hasText]);

  const placeholder = hasContext
    ? selectedNodes.length === 1
      ? `Ask about this ${selectedNodes[0].node_type.replace(/_/g, " ")}...`
      : "Compare, ask about connections, or explore..."
    : surface === "board" && !isFocused && !hasText
      ? BOARD_PLACEHOLDERS[rotatingIndex]
      : defaults.placeholder;

  // Show surface-specific suggestions when no context, or context-based when nodes selected
  const showSuggestions = !hasText;

  return (
    <div className="absolute bottom-6 left-1/2 z-10 w-full max-w-2xl -translate-x-1/2 px-4">
      <div className="rounded-2xl border bg-background shadow-lg transition-all duration-200 overflow-hidden">
        {/* Context bar */}
        {showContextBar && (
          <ChatContextBar
            nodes={selectedNodes}
            previewNode={previewNode}
            onClear={onClearSelection ?? (() => {})}
            onRemove={onRemoveNode}
          />
        )}

        {/* Suggestion chips */}
        {showSuggestions && (
          <ChatSuggestions
            selectedNodes={selectedNodes}
            onSelect={handleSuggestion}
            defaultSuggestions={defaults.suggestions}
          />
        )}

        {/* Textarea */}
        <div className="px-4 pt-2 pb-1">
          <textarea
            ref={textareaRef}
            rows={1}
            value={input}
            onChange={(e) => setInput(e.target.value)}
            onFocus={() => setIsFocused(true)}
            onBlur={() => setIsFocused(false)}
            placeholder={placeholder}
            className="w-full resize-none bg-transparent text-sm leading-relaxed placeholder:text-muted-foreground focus:outline-none"
            style={{ minHeight: "24px", maxHeight: "160px" }}
            onKeyDown={(e) => {
              if (e.key === "Enter" && !e.shiftKey) {
                e.preventDefault();
                handleSubmit();
              }
            }}
          />
        </div>

        {/* Bottom row */}
        <div className="flex items-center justify-between px-3 pb-2.5">
          {projectId ? (
            <UniversalActionMenu projectId={projectId} />
          ) : (
            <div className="w-7" />
          )}

          <div className="flex items-center gap-1.5">
            <Popover open={agentOpen} onOpenChange={setAgentOpen}>
              <PopoverTrigger asChild>
                <button
                  className="flex items-center gap-1 rounded-md px-2 py-1 text-xs text-muted-foreground hover:bg-muted/50 transition-colors"
                  type="button"
                >
                  <ChevronDown className="h-3 w-3" />
                  {activeAgent.label}
                </button>
              </PopoverTrigger>
              <PopoverContent align="end" className="w-44 p-1" sideOffset={8}>
                {AGENTS.map((a) => {
                  const Icon = a.icon;
                  return (
                    <button
                      key={a.slug}
                      className={`flex w-full items-center gap-2 rounded-md px-2.5 py-1.5 text-xs transition-colors hover:bg-muted ${a.slug === agent ? "bg-muted font-medium" : ""}`}
                      onClick={() => {
                        onAgentChange?.(a.slug);
                        setAgentOpen(false);
                      }}
                      type="button"
                    >
                      <Icon className="h-3.5 w-3.5 text-muted-foreground" />
                      {a.label}
                    </button>
                  );
                })}
              </PopoverContent>
            </Popover>

            <Button
              size="icon"
              variant={hasText ? "default" : "ghost"}
              className="h-8 w-8 shrink-0 rounded-lg"
              onClick={handleSubmit}
              disabled={!hasText}
            >
              <ArrowUp className="h-4 w-4" />
            </Button>
          </div>
        </div>
      </div>
    </div>
  );
}
