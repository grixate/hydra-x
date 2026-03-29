import { Card, CardContent } from "@/components/ui/card";
import { ScrollArea } from "@/components/ui/scroll-area";
import { NodeTypeIcon, nodeTypeLabel } from "./node-type-icon";
import { StatusBadge } from "./status-badge";
import { cn } from "@/lib/utils";

interface NodeItem {
  id: number;
  title: string;
  body?: string;
  status: string;
  node_type?: string;
  updated_at?: string;
  [key: string]: unknown;
}

interface NodeListProps<T extends NodeItem> {
  items: T[];
  nodeType: string;
  selectedId?: number | null;
  onSelect?: (item: T) => void;
  renderCard?: (item: T) => React.ReactNode;
  emptyMessage?: string;
  className?: string;
}

export function NodeList<T extends NodeItem>({
  items,
  nodeType,
  selectedId,
  onSelect,
  renderCard,
  emptyMessage,
  className,
}: NodeListProps<T>) {
  if (items.length === 0) {
    return (
      <Card>
        <CardContent className="flex flex-col items-center justify-center py-12 text-center">
          <NodeTypeIcon nodeType={nodeType} className="mb-3 h-8 w-8 text-muted-foreground" />
          <p className="text-sm text-muted-foreground">
            {emptyMessage ?? `No ${nodeTypeLabel(nodeType).toLowerCase()}s yet.`}
          </p>
        </CardContent>
      </Card>
    );
  }

  return (
    <ScrollArea className={cn("max-h-[70vh]", className)}>
      <div className="space-y-2">
        {items.map((item) =>
          renderCard ? (
            <div key={item.id} onClick={() => onSelect?.(item)} className="cursor-pointer">
              {renderCard(item)}
            </div>
          ) : (
            <button
              key={item.id}
              type="button"
              onClick={() => onSelect?.(item)}
              className={cn(
                "w-full rounded-[1.3rem] border p-4 text-left transition-colors",
                selectedId === item.id
                  ? "border-foreground bg-foreground text-background"
                  : "border-border bg-[rgba(255,252,247,0.88)] hover:border-primary",
              )}
            >
              <div className="flex items-start justify-between gap-2">
                <div className="flex items-start gap-2 min-w-0 flex-1">
                  <NodeTypeIcon
                    nodeType={item.node_type ?? nodeType}
                    className="mt-0.5 h-4 w-4 shrink-0 opacity-60"
                  />
                  <div className="min-w-0">
                    <p className="text-sm font-medium leading-tight truncate">{item.title}</p>
                    {item.body && (
                      <p className="mt-1 text-xs opacity-60 line-clamp-2">
                        {item.body.slice(0, 120)}
                      </p>
                    )}
                  </div>
                </div>
                <StatusBadge status={item.status} />
              </div>
            </button>
          ),
        )}
      </div>
    </ScrollArea>
  );
}
