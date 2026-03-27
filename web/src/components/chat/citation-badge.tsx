import { Badge } from "@/components/ui/badge";

export function CitationBadge({
  index,
  onClick,
}: {
  index: number;
  onClick?: () => void;
}) {
  return (
    <button type="button" onClick={onClick} className="ml-1 align-middle">
      <Badge variant="accent">[{index}]</Badge>
    </button>
  );
}
