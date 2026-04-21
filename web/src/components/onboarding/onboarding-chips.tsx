import { Sparkles, Lightbulb, X } from "lucide-react";

export function OnboardingChips({
  onPrefill,
  onSend,
  onSkip,
  disabled,
}: {
  onPrefill: (text: string) => void;
  onSend: (text: string) => void;
  onSkip: () => void;
  disabled?: boolean;
}) {
  return (
    <div className="flex flex-wrap gap-1.5 px-3 pt-2">
      <Chip
        icon={<Sparkles className="h-3 w-3" />}
        onClick={() => onPrefill("I'm building a product for ")}
        disabled={disabled}
      >
        I'm building a product for…
      </Chip>
      <Chip
        icon={<Lightbulb className="h-3 w-3" />}
        onClick={() => onSend("Help me think — I'm not sure yet what I'm building.")}
        disabled={disabled}
      >
        Help me think
      </Chip>
      <Chip
        icon={<X className="h-3 w-3" />}
        onClick={onSkip}
        disabled={disabled}
        muted
      >
        Skip for now
      </Chip>
    </div>
  );
}

function Chip({
  icon,
  onClick,
  disabled,
  muted,
  children,
}: {
  icon: React.ReactNode;
  onClick: () => void;
  disabled?: boolean;
  muted?: boolean;
  children: React.ReactNode;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      className={[
        "inline-flex items-center gap-1 rounded-full border px-2.5 py-1 text-[11px] transition-colors",
        muted
          ? "bg-transparent text-muted-foreground hover:bg-muted/60"
          : "bg-primary/10 text-primary hover:bg-primary/20",
        disabled ? "opacity-50 pointer-events-none" : "",
      ].join(" ")}
    >
      {icon}
      <span>{children}</span>
    </button>
  );
}
