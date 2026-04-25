import { useState } from "react";
import { FileText, Lightbulb, Compass, ArrowRight } from "lucide-react";

import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";

export type OnboardingScenario =
  | "materials"
  | "idea"
  | "explore"
  | "just_start"
  | "skip";

const CARDS: Array<{
  id: Exclude<OnboardingScenario, "skip">;
  title: string;
  blurb: string;
  icon: typeof FileText;
}> = [
  {
    id: "materials",
    title: "I have materials",
    blurb:
      "Drop in your notes, documents, or links. An agent will read them and propose a starting structure for your project.",
    icon: FileText,
  },
  {
    id: "idea",
    title: "I have an idea",
    blurb:
      "Describe what you're trying to figure out. An agent will help you sketch an initial plan.",
    icon: Lightbulb,
  },
  {
    id: "explore",
    title: "Let me explore",
    blurb: "Quick walkthrough of how Hydra works, then you're free to poke around.",
    icon: Compass,
  },
  {
    id: "just_start",
    title: "Just start",
    blurb: "Skip the intro and begin a conversation about your project.",
    icon: ArrowRight,
  },
];

export function ForkScreen({
  projectName,
  onSelect,
}: {
  projectName: string;
  onSelect: (scenario: OnboardingScenario) => void;
}) {
  const [busy, setBusy] = useState<OnboardingScenario | null>(null);

  function pick(scenario: OnboardingScenario) {
    if (busy) return;
    setBusy(scenario);
    onSelect(scenario);
  }

  return (
    <div className="fixed inset-0 z-50 flex flex-col bg-background text-foreground">
      <header className="flex items-center justify-between px-6 py-4">
        <p className="text-[11px] font-medium uppercase tracking-[0.2em] text-muted-foreground">
          {projectName}
        </p>
        <Button
          size="sm"
          variant="ghost"
          onClick={() => pick("skip")}
          disabled={busy !== null}
          className="text-xs text-muted-foreground"
        >
          Skip — I'll figure it out
        </Button>
      </header>

      <div className="flex flex-1 items-center justify-center px-6 pb-12">
        <div className="w-full max-w-5xl">
          <div className="mb-10 text-center">
            <h1 className="text-3xl font-semibold tracking-tight">
              How would you like to start?
            </h1>
            <p className="mt-2 text-sm text-muted-foreground">
              Pick the path that fits — you can always change direction later.
            </p>
          </div>

          <div className="grid gap-4 sm:grid-cols-2">
            {CARDS.map((card) => (
              <button
                key={card.id}
                type="button"
                onClick={() => pick(card.id)}
                disabled={busy !== null}
                className={cn(
                  "group flex flex-col gap-3 rounded-xl border bg-card p-6 text-left transition",
                  "hover:border-primary/60 hover:bg-accent/40 focus:outline-none focus:ring-2 focus:ring-primary",
                  busy === card.id && "border-primary/60 bg-accent/40",
                  busy !== null && busy !== card.id && "opacity-50",
                )}
              >
                <div className="flex h-10 w-10 items-center justify-center rounded-full bg-primary/10 text-primary">
                  <card.icon className="h-5 w-5" />
                </div>
                <h2 className="text-base font-semibold">{card.title}</h2>
                <p className="text-sm leading-relaxed text-muted-foreground">
                  {card.blurb}
                </p>
              </button>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}
