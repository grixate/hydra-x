import { useState } from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";

type AgentSpend = {
  persona: string;
  tokens: number;
  cost_cents: number;
  by_model: Array<{ model: string; tokens_in: number; tokens_out: number; cost_cents: number }>;
};

const AGENT_LABELS: Record<string, string> = {
  researcher: "Researcher",
  strategist: "Strategist",
  architect: "Architect",
  designer: "Designer",
  memory_agent: "Memory",
};

const AGENT_COLORS: Record<string, string> = {
  researcher: "#3b82f6",
  strategist: "#f59e0b",
  architect: "#64748b",
  designer: "#8b5cf6",
  memory_agent: "#10b981",
};

function formatTokens(t: number): string {
  if (t >= 1_000_000) return `${(t / 1_000_000).toFixed(1)}M`;
  if (t >= 1_000) return `${(t / 1_000).toFixed(0)}K`;
  return String(t);
}

interface AgentBreakdownProps {
  data: AgentSpend[];
}

export function AgentBreakdown({ data }: AgentBreakdownProps) {
  const [expanded, setExpanded] = useState<string | null>(null);
  const totalCost = Math.max(1, data.reduce((s, a) => s + a.cost_cents, 0));

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-sm font-medium">Spend by agent</CardTitle>
      </CardHeader>
      <CardContent>
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead className="w-[140px]">Agent</TableHead>
              <TableHead className="text-right">Tokens</TableHead>
              <TableHead className="text-right">Cost</TableHead>
              <TableHead className="text-right w-[60px]">%</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {data.flatMap((agent) => {
              const pct = Math.round((agent.cost_cents / totalCost) * 100);
              const rows = [
                <TableRow
                  key={agent.persona}
                  className="cursor-pointer hover:bg-muted/50"
                  onClick={() =>
                    setExpanded(expanded === agent.persona ? null : agent.persona)
                  }
                >
                  <TableCell>
                    <div className="flex items-center gap-2">
                      <div
                        className="h-2 w-2 rounded-full"
                        style={{ backgroundColor: AGENT_COLORS[agent.persona] ?? "#6b7280" }}
                      />
                      <span className="text-sm font-medium">
                        {AGENT_LABELS[agent.persona] ?? agent.persona}
                      </span>
                    </div>
                  </TableCell>
                  <TableCell className="text-right text-sm text-muted-foreground">
                    {formatTokens(agent.tokens)}
                  </TableCell>
                  <TableCell className="text-right text-sm font-medium">
                    ${(agent.cost_cents / 100).toFixed(2)}
                  </TableCell>
                  <TableCell className="text-right text-sm text-muted-foreground">
                    {pct}%
                  </TableCell>
                </TableRow>,
              ];

              if (expanded === agent.persona) {
                for (const m of agent.by_model) {
                  rows.push(
                    <TableRow key={`${agent.persona}-${m.model}`} className="bg-muted/30">
                      <TableCell className="pl-8">
                        <span className="text-xs text-muted-foreground">{m.model}</span>
                      </TableCell>
                      <TableCell className="text-right text-xs text-muted-foreground">
                        {formatTokens(m.tokens_in)} in / {formatTokens(m.tokens_out)} out
                      </TableCell>
                      <TableCell className="text-right text-xs">
                        ${(m.cost_cents / 100).toFixed(2)}
                      </TableCell>
                      <TableCell />
                    </TableRow>,
                  );
                }
              }

              return rows;
            })}
          </TableBody>
        </Table>
      </CardContent>
    </Card>
  );
}
