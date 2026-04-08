import { motion } from "motion/react";

interface TrailSectionDividerProps {
  label?: string;
}

export function TrailSectionDivider({ label }: TrailSectionDividerProps) {
  return (
    <motion.div
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      transition={{ duration: 0.3 }}
      className="flex items-center gap-3 py-6"
    >
      <div className="h-px flex-1 bg-border" />
      {label && (
        <span className="text-[10px] font-semibold uppercase tracking-widest text-muted-foreground">
          {label}
        </span>
      )}
      <div className="h-px flex-1 bg-border" />
    </motion.div>
  );
}
