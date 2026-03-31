import { useState, useEffect } from "react";
import { api } from "@/lib/api";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { X, Trash2 } from "lucide-react";

interface EdgeDetailPopoverProps {
  edgeId: number;
  kind: string;
  sourceTitle: string;
  targetTitle: string;
  projectId: number;
  position: { x: number; y: number };
  onClose: () => void;
  onDelete: () => void;
}

export function EdgeDetailPopover({
  edgeId,
  kind,
  sourceTitle,
  targetTitle,
  projectId,
  position,
  onClose,
  onDelete,
}: EdgeDetailPopoverProps) {
  const [detail, setDetail] = useState<{
    metadata?: Record<string, unknown>;
    inserted_at?: string;
  } | null>(null);
  const [confirming, setConfirming] = useState(false);

  useEffect(() => {
    api.getGraphEdge(projectId, edgeId).then(setDetail).catch(() => {});
  }, [projectId, edgeId]);

  const handleDelete = async () => {
    if (!confirming) {
      setConfirming(true);
      return;
    }
    await api.deleteGraphEdge(projectId, edgeId);
    onDelete();
  };

  return (
    <Card
      className="absolute z-30 w-56 shadow-lg"
      style={{ left: position.x, top: position.y }}
    >
      <CardContent className="p-3">
        <div className="flex items-start justify-between">
          <Badge variant="outline" className="text-[10px]">
            {kind}
          </Badge>
          <Button
            variant="ghost"
            size="icon"
            className="h-5 w-5"
            onClick={onClose}
          >
            <X className="h-3 w-3" />
          </Button>
        </div>

        <div className="mt-2 text-xs">
          <span className="text-muted-foreground">From:</span>{" "}
          <span className="font-medium truncate">{sourceTitle}</span>
        </div>
        <div className="text-xs">
          <span className="text-muted-foreground">To:</span>{" "}
          <span className="font-medium truncate">{targetTitle}</span>
        </div>

        {detail && (
          <>
            {detail.metadata?.created_by && (
              <div className="mt-1.5 text-[10px] text-muted-foreground">
                Created by: {String(detail.metadata.created_by)}
              </div>
            )}
            {detail.metadata?.reason && (
              <div className="mt-1 text-[10px] text-muted-foreground">
                {String(detail.metadata.reason)}
              </div>
            )}
            {detail.inserted_at && (
              <div className="mt-1 text-[10px] text-muted-foreground">
                {new Date(detail.inserted_at).toLocaleDateString()}
              </div>
            )}
          </>
        )}

        <Button
          variant={confirming ? "destructive" : "outline"}
          size="sm"
          className="mt-3 w-full h-7 text-[11px]"
          onClick={handleDelete}
        >
          <Trash2 className="mr-1 h-3 w-3" />
          {confirming ? "Confirm remove?" : "Remove connection"}
        </Button>
      </CardContent>
    </Card>
  );
}
