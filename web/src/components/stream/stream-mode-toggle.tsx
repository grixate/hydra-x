import { motion } from "motion/react";
import { cn } from "@/lib/utils";

export type StreamMode = "my-work" | "project";

interface StreamModeToggleProps {
  mode: StreamMode;
  onModeChange: (mode: StreamMode) => void;
}

export function StreamModeToggle({ mode, onModeChange }: StreamModeToggleProps) {
  return (
    <div className="relative flex gap-1 rounded-lg bg-muted/50 p-0.5 w-fit">
      {/* Animated pill background */}
      <motion.div
        className="absolute inset-y-0.5 rounded-md bg-background shadow-sm"
        layoutId="stream-mode-pill"
        style={{
          width: "calc(50% - 2px)",
          left: mode === "my-work" ? "2px" : "calc(50%)",
        }}
        transition={{ type: "spring", stiffness: 500, damping: 35 }}
      />
      <button
        onClick={() => onModeChange("my-work")}
        className={cn(
          "relative z-10 rounded-md px-3 py-1.5 text-sm transition-colors",
          mode === "my-work"
            ? "font-medium"
            : "text-muted-foreground hover:text-foreground",
        )}
      >
        My Work
      </button>
      <button
        onClick={() => onModeChange("project")}
        className={cn(
          "relative z-10 rounded-md px-3 py-1.5 text-sm transition-colors",
          mode === "project"
            ? "font-medium"
            : "text-muted-foreground hover:text-foreground",
        )}
      >
        Project
      </button>
    </div>
  );
}
