import type { PropsWithChildren } from "react";

import { cn } from "@/lib/utils";

export function Surface({
  className,
  children,
}: PropsWithChildren<{ className?: string }>) {
  return (
    <section
      className={cn(
        "rounded-[2rem] border border-[var(--line)] bg-white/75 shadow-[0_24px_80px_rgba(30,25,22,0.08)] backdrop-blur-md",
        className,
      )}
    >
      {children}
    </section>
  );
}
