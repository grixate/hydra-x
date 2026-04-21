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

type ModelSpend = {
  model: string;
  tokens_in: number;
  tokens_out: number;
  cost_cents: number;
};

function formatTokens(t: number): string {
  if (t >= 1_000_000) return `${(t / 1_000_000).toFixed(1)}M`;
  if (t >= 1_000) return `${(t / 1_000).toFixed(0)}K`;
  return String(t);
}

interface ModelBreakdownProps {
  data: ModelSpend[];
}

export function ModelBreakdown({ data }: ModelBreakdownProps) {
  const totalCost = Math.max(1, data.reduce((s, m) => s + m.cost_cents, 0));

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-sm font-medium">Spend by model</CardTitle>
      </CardHeader>
      <CardContent>
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead className="w-[180px]">Model</TableHead>
              <TableHead className="text-right">Tokens</TableHead>
              <TableHead className="text-right">Cost</TableHead>
              <TableHead className="text-right w-[60px]">%</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {data.map((m) => {
              const pct = Math.round((m.cost_cents / totalCost) * 100);
              return (
                <TableRow key={m.model}>
                  <TableCell>
                    <span className="text-sm font-medium">{m.model}</span>
                  </TableCell>
                  <TableCell className="text-right text-sm text-muted-foreground">
                    {formatTokens(m.tokens_in + m.tokens_out)}
                  </TableCell>
                  <TableCell className="text-right text-sm font-medium">
                    ${(m.cost_cents / 100).toFixed(2)}
                  </TableCell>
                  <TableCell className="text-right text-sm text-muted-foreground">
                    {pct}%
                  </TableCell>
                </TableRow>
              );
            })}
          </TableBody>
        </Table>
      </CardContent>
    </Card>
  );
}
