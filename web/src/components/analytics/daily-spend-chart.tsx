type DailySpend = { date: string; tokens: number; cost_cents: number };

interface DailySpendChartProps {
  data: DailySpend[];
}

export function DailySpendChart({ data }: DailySpendChartProps) {
  if (data.length === 0) {
    return (
      <div className="flex items-center justify-center h-40 text-xs text-muted-foreground">
        No spend data yet
      </div>
    );
  }

  const maxCost = Math.max(1, ...data.map((d) => d.cost_cents));
  const width = 600;
  const height = 160;
  const pad = { top: 20, right: 20, bottom: 30, left: 50 };

  const xScale = (i: number) =>
    pad.left + (data.length > 1 ? (i / (data.length - 1)) * (width - pad.left - pad.right) : (width - pad.left - pad.right) / 2);
  const yScale = (cents: number) =>
    height - pad.bottom - (cents / maxCost) * (height - pad.top - pad.bottom);

  const pathD = data
    .map((d, i) => `${i === 0 ? "M" : "L"} ${xScale(i)} ${yScale(d.cost_cents)}`)
    .join(" ");

  return (
    <svg viewBox={`0 0 ${width} ${height}`} className="w-full">
      {/* Grid lines */}
      {[0, 0.25, 0.5, 0.75, 1].map((pct) => (
        <line
          key={pct}
          x1={pad.left}
          x2={width - pad.right}
          y1={yScale(maxCost * pct)}
          y2={yScale(maxCost * pct)}
          stroke="hsl(var(--border))"
          strokeWidth={0.5}
        />
      ))}

      {/* Line */}
      <path d={pathD} fill="none" stroke="hsl(var(--primary))" strokeWidth={1.5} />

      {/* Dots */}
      {data.map((d, i) => (
        <circle
          key={i}
          cx={xScale(i)}
          cy={yScale(d.cost_cents)}
          r={3}
          fill="hsl(var(--primary))"
          className="cursor-pointer"
        >
          <title>
            {d.date}: ${(d.cost_cents / 100).toFixed(2)}
          </title>
        </circle>
      ))}

      {/* Y axis labels */}
      <text
        x={pad.left - 8}
        y={yScale(maxCost) + 4}
        textAnchor="end"
        className="text-[9px]"
        fill="hsl(var(--muted-foreground))"
      >
        ${(maxCost / 100).toFixed(2)}
      </text>
      <text
        x={pad.left - 8}
        y={yScale(0) + 4}
        textAnchor="end"
        className="text-[9px]"
        fill="hsl(var(--muted-foreground))"
      >
        $0
      </text>

      {/* X axis labels */}
      {data.length > 0 && (
        <>
          <text
            x={xScale(0)}
            y={height - 8}
            textAnchor="start"
            className="text-[9px]"
            fill="hsl(var(--muted-foreground))"
          >
            {data[0].date.slice(5)}
          </text>
          <text
            x={xScale(data.length - 1)}
            y={height - 8}
            textAnchor="end"
            className="text-[9px]"
            fill="hsl(var(--muted-foreground))"
          >
            {data[data.length - 1].date.slice(5)}
          </text>
        </>
      )}
    </svg>
  );
}
