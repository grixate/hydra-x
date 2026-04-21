import { useState } from "react";
import {
  AreaChart,
  Area,
  XAxis,
  YAxis,
  Tooltip,
  ResponsiveContainer,
  CartesianGrid,
} from "recharts";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { cn } from "@/lib/utils";

type DailyData = { date: string; cost_cents: number; [key: string]: unknown };

interface SpendChartProps {
  data: DailyData[];
}

const AGENT_COLORS: Record<string, string> = {
  researcher: "#3b82f6",
  strategist: "#f59e0b",
  architect: "#64748b",
  designer: "#8b5cf6",
  memory_agent: "#10b981",
};

export function SpendChart({ data }: SpendChartProps) {
  const [showByAgent, setShowByAgent] = useState(false);

  const hasAgentData = data.length > 0 && "researcher" in data[0];

  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between pb-2">
        <CardTitle className="text-sm font-medium">Daily spend</CardTitle>
        {hasAgentData && (
          <button
            onClick={() => setShowByAgent(!showByAgent)}
            className={cn(
              "rounded-md px-2.5 py-1 text-xs transition-colors",
              showByAgent
                ? "bg-primary text-primary-foreground"
                : "text-muted-foreground hover:bg-muted",
            )}
          >
            By agent
          </button>
        )}
      </CardHeader>
      <CardContent>
        {data.length === 0 ? (
          <div className="flex items-center justify-center h-[240px] text-sm text-muted-foreground">
            No spend data for this period
          </div>
        ) : (
          <ResponsiveContainer width="100%" height={240}>
            <AreaChart data={data}>
              <CartesianGrid strokeDasharray="3 3" stroke="hsl(var(--border))" />
              <XAxis
                dataKey="date"
                tickFormatter={(d: string) => {
                  // Parse "2026-04-09" directly to avoid timezone shift
                  const parts = d.split("-");
                  if (parts.length === 3) {
                    const months = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"];
                    return `${months[parseInt(parts[1], 10) - 1]} ${parseInt(parts[2], 10)}`;
                  }
                  return d;
                }}
                tick={{ fontSize: 11, fill: "hsl(var(--muted-foreground))" }}
                axisLine={{ stroke: "hsl(var(--border))" }}
              />
              <YAxis
                tickFormatter={(v) => `$${(v / 100).toFixed(0)}`}
                tick={{ fontSize: 11, fill: "hsl(var(--muted-foreground))" }}
                axisLine={false}
                tickLine={false}
                width={48}
              />
              <Tooltip
                content={({ active, payload, label }) => {
                  if (!active || !payload?.length) return null;
                  return (
                    <div className="rounded-lg border bg-background px-3 py-2 shadow-md">
                      <p className="text-xs text-muted-foreground">{label}</p>
                      {payload
                        .filter((p) => p.value != null && (p.value as number) > 0)
                        .map((p, i) => (
                          <p key={i} className="text-sm font-medium">
                            {p.name}: ${((p.value as number) / 100).toFixed(2)}
                          </p>
                        ))}
                    </div>
                  );
                }}
              />
              {showByAgent && hasAgentData ? (
                <>
                  {Object.entries(AGENT_COLORS).map(([key, color]) => (
                    <Area
                      key={key}
                      type="monotone"
                      dataKey={key}
                      stackId="1"
                      fill={color}
                      fillOpacity={0.3}
                      stroke={color}
                      strokeWidth={1.5}
                    />
                  ))}
                </>
              ) : (
                <Area
                  type="monotone"
                  dataKey="cost_cents"
                  name="Total"
                  fill="hsl(var(--primary))"
                  fillOpacity={0.1}
                  stroke="hsl(var(--primary))"
                  strokeWidth={2}
                />
              )}
            </AreaChart>
          </ResponsiveContainer>
        )}
      </CardContent>
    </Card>
  );
}
