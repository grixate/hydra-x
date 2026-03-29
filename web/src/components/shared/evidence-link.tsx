import { Link2 } from "lucide-react";

import { Badge } from "@/components/ui/badge";

export function EvidenceLink({
  label,
  onClick,
}: {
  label: string;
  onClick?: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="inline-flex items-center gap-2 text-left"
    >
      <Badge variant="accent">{label}</Badge>
      <span className="inline-flex items-center gap-1 text-xs text-muted-foreground">
        <Link2 className="h-3.5 w-3.5" />
        evidence
      </span>
    </button>
  );
}
