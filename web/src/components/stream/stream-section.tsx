import { Badge } from "@/components/ui/badge";

interface StreamSectionProps {
  title: string;
  count: number;
  children: React.ReactNode;
}

export function StreamSection({ title, count, children }: StreamSectionProps) {
  return (
    <div className="space-y-3">
      <div className="flex items-center gap-2">
        <h3 className="text-xs font-semibold uppercase tracking-widest text-muted-foreground">
          {title}
        </h3>
        {count > 0 && (
          <Badge variant="secondary" className="text-[10px]">
            {count}
          </Badge>
        )}
      </div>
      <div className="grid gap-3 md:grid-cols-2">{children}</div>
    </div>
  );
}
