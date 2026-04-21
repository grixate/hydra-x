interface ActivityHeatmapProps {
  data: number[][];  // 7 arrays (Mon-Sun) of 24 numbers (hours 0-23), value 0-5
}

const DAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

export function ActivityHeatmap({ data }: ActivityHeatmapProps) {
  if (!data || data.length !== 7) return null;

  return (
    <div className="space-y-0.5">
      {DAYS.map((day, di) => (
        <div key={day} className="flex items-center gap-1">
          <span className="w-7 text-[9px] text-muted-foreground">{day}</span>
          <div className="flex gap-px">
            {(data[di] ?? []).map((level, hi) => (
              <div
                key={hi}
                className="h-2 w-1.5 rounded-sm"
                style={{
                  backgroundColor:
                    level === 0
                      ? "hsl(var(--muted))"
                      : `hsl(var(--primary) / ${0.2 + level * 0.16})`,
                }}
                title={`${day} ${hi}:00 — ${level > 0 ? "active" : "idle"}`}
              />
            ))}
          </div>
        </div>
      ))}
      <div className="flex items-center gap-1 mt-1 ml-8">
        <span className="text-[8px] text-muted-foreground">0</span>
        <div className="flex-1" />
        <span className="text-[8px] text-muted-foreground">12</span>
        <div className="flex-1" />
        <span className="text-[8px] text-muted-foreground">24</span>
      </div>
    </div>
  );
}
