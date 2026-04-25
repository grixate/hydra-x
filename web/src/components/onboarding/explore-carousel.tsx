import { useState } from "react";
import {
  Activity,
  Layers,
  Network,
  BookOpen,
  Users,
  ArrowRight,
  X,
} from "lucide-react";
import type { LucideIcon } from "lucide-react";

import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";

type Slide = {
  id: string;
  title: string;
  body: string;
  icon: LucideIcon;
};

const SLIDES: Slide[] = [
  {
    id: "stream",
    title: "Stream",
    body: "Your project's activity feed. Agents post updates here when they propose, complete, or get stuck on tasks. The 'Needs You' tab shows what's waiting on you.",
    icon: Activity,
  },
  {
    id: "board",
    title: "Board",
    body: "A canvas for working out ideas before they become structured. Drag, sketch, connect. When something's ready, promote it into the project's graph.",
    icon: Layers,
  },
  {
    id: "graph",
    title: "Graph",
    body: "Everything in your project — insights, decisions, requirements, evidence — typed and linked. Click anything to see what supports it and what it leads to.",
    icon: Network,
  },
  {
    id: "library",
    title: "Library",
    body: "All your sources and reference materials. Agents read these to ground their reasoning, so what they tell you is traceable to something real.",
    icon: BookOpen,
  },
  {
    id: "agents",
    title: "Agents",
    body: "A team of specialized agents work on your project: research, strategy, design, memory. You can configure them, add new ones, or have them collaborate on tasks.",
    icon: Users,
  },
];

const OUTRO =
  "You're set. Start poking around — agents will introduce themselves when relevant.";

export function ExploreCarousel({ onDismiss }: { onDismiss: () => void }) {
  const [index, setIndex] = useState(0);
  const isLast = index === SLIDES.length - 1;
  const slide = SLIDES[index];
  const Icon = slide.icon;

  function next() {
    if (isLast) {
      onDismiss();
    } else {
      setIndex((i) => i + 1);
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex flex-col bg-background text-foreground">
      <header className="flex items-center justify-between px-6 py-4">
        <div className="flex items-center gap-2 text-[11px] uppercase tracking-[0.2em] text-muted-foreground">
          <span>Explore Hydra</span>
          <span className="text-muted-foreground/60">
            {index + 1} / {SLIDES.length}
          </span>
        </div>
        <Button
          size="sm"
          variant="ghost"
          onClick={onDismiss}
          aria-label="Dismiss tour"
          className="text-xs text-muted-foreground"
        >
          <X className="mr-1 h-3.5 w-3.5" />
          Dismiss
        </Button>
      </header>

      <div className="flex flex-1 items-center justify-center px-6 pb-12">
        <div className="w-full max-w-2xl text-center">
          <div className="mx-auto mb-8 flex h-20 w-20 items-center justify-center rounded-full bg-primary/10 text-primary">
            <Icon className="h-9 w-9" />
          </div>
          <h2 className="text-3xl font-semibold tracking-tight">{slide.title}</h2>
          <p className="mt-4 text-base leading-relaxed text-muted-foreground">
            {slide.body}
          </p>
          {isLast ? (
            <p className="mt-6 text-sm leading-relaxed text-foreground">{OUTRO}</p>
          ) : null}

          <div className="mt-10 flex items-center justify-center gap-2">
            {SLIDES.map((s, i) => (
              <button
                key={s.id}
                type="button"
                onClick={() => setIndex(i)}
                aria-label={`Go to slide ${i + 1}`}
                className={cn(
                  "h-1.5 w-6 rounded-full transition",
                  i === index ? "bg-primary" : "bg-border hover:bg-muted-foreground/40",
                )}
              />
            ))}
          </div>

          <div className="mt-6">
            <Button onClick={next} size="lg">
              {isLast ? "Start" : "Next"}
              <ArrowRight className="ml-2 h-4 w-4" />
            </Button>
          </div>
        </div>
      </div>
    </div>
  );
}
