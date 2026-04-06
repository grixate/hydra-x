import { useState } from "react";
import type { StreamItem as StreamItemType } from "@/lib/api";
import { StreamItem } from "./stream-item";
import { StreamSection } from "./stream-section";
import { Card, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { ChevronDown, ChevronRight } from "lucide-react";

interface StreamViewProps {
  rightNow: StreamItemType[];
  recently: StreamItemType[];
  emerging: StreamItemType[];
  onNavigateToNode?: (nodeType: string, nodeId: number) => void;
  onNavigateGraph?: (nodeType: string, nodeId: number, filterType: string) => void;
  onAction?: (action: string, item: StreamItemType) => void;
}

function StreamGroup({
  item,
  onNavigate,
  onNavigateGraph,
  onAction,
}: {
  item: StreamItemType;
  onNavigate?: (nodeType: string, nodeId: number) => void;
  onNavigateGraph?: (nodeType: string, nodeId: number, filterType: string) => void;
  onAction?: (action: string, item: StreamItemType) => void;
}) {
  const [expanded, setExpanded] = useState(false);
  const children = item.items ?? [];

  return (
    <Card className="col-span-full">
      <CardContent className="p-4 space-y-2">
        <div
          className="flex items-center gap-2 cursor-pointer"
          onClick={() => setExpanded(!expanded)}
        >
          {expanded ? (
            <ChevronDown className="h-3.5 w-3.5 text-muted-foreground" />
          ) : (
            <ChevronRight className="h-3.5 w-3.5 text-muted-foreground" />
          )}
          <span className="text-sm font-semibold">{item.title}</span>
          <Badge variant="secondary" className="text-[10px]">
            {children.length}
          </Badge>
        </div>
        {item.narrative && (
          <p className="ml-5.5 text-xs italic text-muted-foreground">
            {item.narrative}
          </p>
        )}
        {expanded && (
          <div className="grid gap-2 mt-2">
            {children.map((child) => (
              <StreamItem
                key={child.id}
                item={child}
                onNavigate={onNavigate}
                onNavigateGraph={onNavigateGraph}
                onAction={onAction}
              />
            ))}
          </div>
        )}
      </CardContent>
    </Card>
  );
}

function renderStreamItem(
  item: StreamItemType,
  onNavigate?: (nodeType: string, nodeId: number) => void,
  onNavigateGraph?: (nodeType: string, nodeId: number, filterType: string) => void,
  onAction?: (action: string, item: StreamItemType) => void,
) {
  if (item.type === "group") {
    return (
      <StreamGroup
        key={item.id}
        item={item}
        onNavigate={onNavigate}
        onNavigateGraph={onNavigateGraph}
        onAction={onAction}
      />
    );
  }
  return (
    <StreamItem
      key={item.id}
      item={item}
      onNavigate={onNavigate}
      onNavigateGraph={onNavigateGraph}
      onAction={onAction}
    />
  );
}

export function StreamView({
  rightNow,
  recently,
  emerging,
  onNavigateToNode,
  onNavigateGraph,
  onAction,
}: StreamViewProps) {
  const isEmpty =
    rightNow.length === 0 && recently.length === 0 && emerging.length === 0;

  if (isEmpty) {
    return (
      <Card>
        <CardContent className="flex flex-col items-center justify-center py-16 text-center">
          <p className="text-lg font-semibold">You're caught up</p>
          <p className="mt-1 text-sm text-muted-foreground">
            Nothing needs your attention right now.
          </p>
        </CardContent>
      </Card>
    );
  }

  return (
    <div className="space-y-8">
      {rightNow.length > 0 && (
        <StreamSection title="Needs attention" count={rightNow.length}>
          {rightNow.map((item) =>
            renderStreamItem(item, onNavigateToNode, onNavigateGraph, onAction)
          )}
        </StreamSection>
      )}

      {recently.length > 0 && (
        <StreamSection title="Recent activity" count={recently.length}>
          {recently.map((item) =>
            renderStreamItem(item, onNavigateToNode, onNavigateGraph, onAction)
          )}
        </StreamSection>
      )}

      {emerging.length > 0 && (
        <StreamSection title="On the horizon" count={emerging.length}>
          {emerging.map((item) =>
            renderStreamItem(item, onNavigateToNode, onNavigateGraph, onAction)
          )}
        </StreamSection>
      )}
    </div>
  );
}
