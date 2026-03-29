import type { StreamItem as StreamItemType } from "@/lib/api";
import { StreamItem } from "./stream-item";
import { StreamSection } from "./stream-section";
import { Card, CardContent } from "@/components/ui/card";

interface StreamViewProps {
  rightNow: StreamItemType[];
  recently: StreamItemType[];
  emerging: StreamItemType[];
  onNavigateToNode?: (nodeType: string, nodeId: number) => void;
  onAction?: (action: string, item: StreamItemType) => void;
}

export function StreamView({
  rightNow,
  recently,
  emerging,
  onNavigateToNode,
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
          {rightNow.map((item) => (
            <StreamItem
              key={item.id}
              item={item}
              onNavigate={onNavigateToNode}
              onAction={onAction}
            />
          ))}
        </StreamSection>
      )}

      {recently.length > 0 && (
        <StreamSection title="Recent activity" count={recently.length}>
          {recently.map((item) => (
            <StreamItem
              key={item.id}
              item={item}
              onNavigate={onNavigateToNode}
              onAction={onAction}
            />
          ))}
        </StreamSection>
      )}

      {emerging.length > 0 && (
        <StreamSection title="On the horizon" count={emerging.length}>
          {emerging.map((item) => (
            <StreamItem
              key={item.id}
              item={item}
              onNavigate={onNavigateToNode}
              onAction={onAction}
            />
          ))}
        </StreamSection>
      )}
    </div>
  );
}
