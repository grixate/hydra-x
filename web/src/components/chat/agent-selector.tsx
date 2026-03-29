import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";

const personas = [
  {
    id: "researcher",
    label: "Researcher",
    description: "Pattern-finding and evidence-backed synthesis",
  },
  {
    id: "strategist",
    label: "Strategist",
    description: "Requirement framing with traceable rationale",
  },
] as const;

export function AgentSelector({
  value,
  onChange,
}: {
  value: string;
  onChange: (persona: "researcher" | "strategist") => void;
}) {
  const current = personas.find((persona) => persona.id === value) ?? personas[0];

  return (
    <div className="space-y-2">
      <Select value={value} onValueChange={(next) => onChange(next as "researcher" | "strategist")}>
        <SelectTrigger>
          <SelectValue placeholder="Select agent persona" />
        </SelectTrigger>
        <SelectContent>
          {personas.map((persona) => (
            <SelectItem key={persona.id} value={persona.id}>
              {persona.label}
            </SelectItem>
          ))}
        </SelectContent>
      </Select>
      <p className="text-sm text-muted-foreground">{current.description}</p>
    </div>
  );
}
