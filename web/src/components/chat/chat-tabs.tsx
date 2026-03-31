import { Button } from "@/components/ui/button";
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover";
import { Plus, Minus, Maximize2, X } from "lucide-react";
import { cn } from "@/lib/utils";

const AGENT_COLORS: Record<string, string> = {
  memory: "#6366f1",
  researcher: "#3b82f6",
  strategist: "#14b8a6",
  architect: "#f59e0b",
  designer: "#8b5cf6",
};

const AGENT_ABBREV: Record<string, string> = {
  memory: "Mem",
  researcher: "Res",
  strategist: "Str",
  architect: "Arc",
  designer: "Des",
};

const ALL_AGENTS = ["memory", "researcher", "strategist", "architect", "designer"];

export interface ChatTab {
  agent: string;
  conversationId: number | null;
  messages: Array<{ role: string; content: string; timestamp: string }>;
  unread: number;
}

interface GraphChatTabsProps {
  tabs: ChatTab[];
  activeIndex: number;
  minimized: boolean;
  onTabClick: (index: number) => void;
  onAddTab: (agent: string) => void;
  onMinimize: () => void;
  onClose: () => void;
}

export function GraphChatTabs({
  tabs,
  activeIndex,
  minimized,
  onTabClick,
  onAddTab,
  onMinimize,
  onClose,
}: GraphChatTabsProps) {
  const openAgents = new Set(tabs.map((t) => t.agent));
  const availableAgents = ALL_AGENTS.filter((a) => !openAgents.has(a));

  return (
    <div className="flex items-center border-b">
      <div className="flex flex-1 items-center overflow-x-auto">
        {tabs.map((tab, i) => (
          <button
            key={tab.agent}
            type="button"
            onClick={() => onTabClick(i)}
            className={cn(
              "flex items-center gap-1.5 px-3 py-2 text-xs transition-colors border-b-2 shrink-0",
              i === activeIndex
                ? "border-primary bg-background text-foreground font-medium"
                : "border-transparent bg-muted/30 text-muted-foreground hover:text-foreground",
            )}
          >
            <span
              className="h-2 w-2 rounded-full shrink-0"
              style={{ backgroundColor: AGENT_COLORS[tab.agent] ?? "#6b7280" }}
            />
            {tabs.length > 3 ? AGENT_ABBREV[tab.agent] ?? tab.agent : tab.agent}
            {tab.unread > 0 && (
              <span className="ml-0.5 rounded-full bg-primary px-1 text-[9px] text-primary-foreground">
                {tab.unread}
              </span>
            )}
          </button>
        ))}

        {availableAgents.length > 0 && (
          <Popover>
            <PopoverTrigger asChild>
              <Button
                variant="ghost"
                size="icon"
                className="h-7 w-7 shrink-0 mx-1"
              >
                <Plus className="h-3 w-3" />
              </Button>
            </PopoverTrigger>
            <PopoverContent align="start" className="w-36 p-1" sideOffset={4}>
              {availableAgents.map((agent) => (
                <button
                  key={agent}
                  type="button"
                  className="flex w-full items-center gap-2 rounded-md px-2.5 py-1.5 text-xs hover:bg-muted transition-colors"
                  onClick={() => onAddTab(agent)}
                >
                  <span
                    className="h-2 w-2 rounded-full"
                    style={{ backgroundColor: AGENT_COLORS[agent] }}
                  />
                  {agent}
                </button>
              ))}
            </PopoverContent>
          </Popover>
        )}
      </div>

      <div className="flex items-center gap-0.5 px-1.5 shrink-0">
        <Button
          variant="ghost"
          size="icon"
          className="h-6 w-6"
          onClick={onMinimize}
        >
          {minimized ? (
            <Maximize2 className="h-3 w-3" />
          ) : (
            <Minus className="h-3 w-3" />
          )}
        </Button>
        <Button
          variant="ghost"
          size="icon"
          className="h-6 w-6"
          onClick={onClose}
        >
          <X className="h-3 w-3" />
        </Button>
      </div>
    </div>
  );
}

export { AGENT_COLORS };
