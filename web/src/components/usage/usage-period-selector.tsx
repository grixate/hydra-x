import { useState } from "react";
import { format } from "date-fns";
import { Calendar as CalendarIcon } from "lucide-react";
import { cn } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import { Calendar } from "@/components/ui/calendar";
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover";

export type Period = "7d" | "30d" | "90d" | "custom";

export type DateRange = {
  from: Date;
  to: Date;
};

interface PeriodSelectorProps {
  period: Period;
  dateRange?: DateRange;
  onChange: (period: Period, dateRange?: DateRange) => void;
}

const PRESETS: { value: Exclude<Period, "custom">; label: string }[] = [
  { value: "7d", label: "7 days" },
  { value: "30d", label: "30 days" },
  { value: "90d", label: "90 days" },
];

export function PeriodSelector({ period, dateRange, onChange }: PeriodSelectorProps) {
  const [calOpen, setCalOpen] = useState(false);
  const [selectedRange, setSelectedRange] = useState<{ from?: Date; to?: Date }>({
    from: dateRange?.from,
    to: dateRange?.to,
  });

  const handlePreset = (p: Exclude<Period, "custom">) => {
    onChange(p);
  };

  const handleRangeSelect = (range: { from?: Date; to?: Date } | undefined) => {
    if (!range) return;
    setSelectedRange(range);
    if (range.from && range.to) {
      onChange("custom", { from: range.from, to: range.to });
      setCalOpen(false);
    }
  };

  const dateLabel =
    period === "custom" && dateRange
      ? `${format(dateRange.from, "MMM d")} – ${format(dateRange.to, "MMM d")}`
      : null;

  return (
    <div className="flex items-center gap-2">
      <div className="flex rounded-lg border bg-muted/50 p-0.5">
        {PRESETS.map((o) => (
          <button
            key={o.value}
            onClick={() => handlePreset(o.value)}
            className={cn(
              "rounded-md px-3 py-1 text-xs transition-colors",
              period === o.value
                ? "bg-background shadow-sm font-medium"
                : "text-muted-foreground hover:text-foreground",
            )}
          >
            {o.label}
          </button>
        ))}
      </div>

      <Popover open={calOpen} onOpenChange={setCalOpen}>
        <PopoverTrigger asChild>
          <Button
            variant={period === "custom" ? "default" : "outline"}
            size="sm"
            className={cn(
              "text-xs gap-1.5",
              period !== "custom" && "text-muted-foreground",
            )}
          >
            <CalendarIcon className="h-3.5 w-3.5" />
            {dateLabel ?? "Custom"}
          </Button>
        </PopoverTrigger>
        <PopoverContent className="w-auto p-0" align="end">
          <Calendar
            mode="range"
            selected={selectedRange as { from: Date; to?: Date }}
            onSelect={handleRangeSelect}
            numberOfMonths={2}
            disabled={(date) => date > new Date()}
          />
        </PopoverContent>
      </Popover>
    </div>
  );
}
