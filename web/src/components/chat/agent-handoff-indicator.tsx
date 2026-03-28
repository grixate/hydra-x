import { Badge } from "@/components/ui/badge";

interface AgentHandoffIndicatorProps {
  fromPersona: string;
  toPersona: string;
}

export function AgentHandoffIndicator({
  fromPersona,
  toPersona,
}: AgentHandoffIndicatorProps) {
  return (
    <div className="my-2 flex items-center gap-2 rounded-lg bg-ink/5 px-3 py-2">
      <span className="text-xs text-ink-soft">Conversation handed off:</span>
      <Badge variant="secondary" className="text-[9px]">
        {fromPersona}
      </Badge>
      <span className="text-xs text-ink-soft">&rarr;</span>
      <Badge variant="default" className="text-[9px]">
        {toPersona}
      </Badge>
    </div>
  );
}
