import type { StreamItem as StreamItemType } from "@/lib/api";
import { StreamItem } from "./stream-item";
import { StreamSection } from "./stream-section";
import { Card, CardContent } from "@/components/ui/card";

interface StreamViewProps {
  rightNow: StreamItemType[];
  recently: StreamItemType[];
  emerging: StreamItemType[];
  onNavigateToNode?: (nodeType: string, nodeId: number) => void;
}

export function StreamView({
  rightNow,
  recently,
  emerging,
  onNavigateToNode,
}: StreamViewProps) {
  const isEmpty =
    rightNow.length === 0 && recently.length === 0 && emerging.length === 0;

  if (isEmpty) {
    return (
      <Card>
        <CardContent className="flex flex-col items-center justify-center py-12 text-center">
          <p className="text-lg font-semibold">You're caught up</p>
          <p className="mt-1 text-sm text-ink-soft">
            No items need your attention right now.
          </p>
        </CardContent>
      </Card>
    );
  }

  return (
    <div className="space-y-6">
      {rightNow.length > 0 && (
        <StreamSection title="Right now" count={rightNow.length}>
          {rightNow.map((item) => (
            <StreamItem
              key={item.id}
              item={item}
              onNavigate={onNavigateToNode}
            />
          ))}
        </StreamSection>
      )}

      {recently.length > 0 && (
        <StreamSection title="Recently" count={recently.length}>
          {recently.map((item) => (
            <StreamItem
              key={item.id}
              item={item}
              onNavigate={onNavigateToNode}
            />
          ))}
        </StreamSection>
      )}

      {emerging.length > 0 && (
        <StreamSection title="Emerging" count={emerging.length}>
          {emerging.map((item) => (
            <StreamItem
              key={item.id}
              item={item}
              onNavigate={onNavigateToNode}
            />
          ))}
        </StreamSection>
      )}
    </div>
  );
}
