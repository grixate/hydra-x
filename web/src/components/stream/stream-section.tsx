import { motion } from "motion/react";
import { Badge } from "@/components/ui/badge";

interface StreamSectionProps {
  title: string;
  count?: number;
  children: React.ReactNode;
}

export function StreamSection({ title, count, children }: StreamSectionProps) {
  return (
    <motion.div
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      transition={{ duration: 0.3 }}
    >
      <div className="flex items-center gap-3 pb-3 pt-6">
        <h2 className="text-xs font-semibold uppercase tracking-widest text-muted-foreground">
          {title}
        </h2>
        {count != null && count > 0 && (
          <Badge variant="secondary" className="text-[10px]">
            {count}
          </Badge>
        )}
      </div>
      {children}
    </motion.div>
  );
}
