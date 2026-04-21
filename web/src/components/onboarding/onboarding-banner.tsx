import { useState } from "react";
import { Compass, Sparkles, User, X } from "lucide-react";
import { useNavigate, useParams } from "react-router-dom";

import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import { useOnboarding } from "@/hooks/use-onboarding";
import { dispatchChatDockAgentSwitch } from "@/components/chat/chat-dock";
import { IdentityBootstrapDialog } from "@/components/onboarding/identity-bootstrap-dialog";
import { showToast } from "@/components/ui/toast-notification";

const OPENING = `Hi — I'm the Strategist. Before we build anything, let's figure out what you're trying to do. In one or two sentences: what problem are you solving, and for whom? Don't overthink it — we'll refine this together.`;

export function OnboardingBanner({ surface }: { surface: "stream" | "graph" }) {
  const { projectId } = useParams<{ projectId: string }>();
  const navigate = useNavigate();
  const pid = projectId ? Number(projectId) : null;
  const { status, start, skip } = useOnboarding(pid);
  const [busy, setBusy] = useState(false);
  const [identityOpen, setIdentityOpen] = useState(false);

  // ChatDock is disabled on Graph in Cycle 1 — if the user starts from a
  // Graph banner, hop to Stream first so the dock is present when we
  // dispatch the agent-switch event.
  async function startConversation() {
    setBusy(true);
    try {
      await start();
      if (surface === "graph" && pid) {
        navigate(`/projects/${pid}/stream`);
      }
      setTimeout(() => dispatchChatDockAgentSwitch("strategist"), 50);
    } finally {
      setBusy(false);
    }
  }

  if (!status) return null;

  if (status.state === "completed") return null;

  if (status.state === "skipped") {
    return (
      <SkippedChip
        hint={status.hint ?? "Pick up with the Strategist when you're ready."}
        onResume={startConversation}
        disabled={busy}
      />
    );
  }

  const adaptiveHeadline =
    status.state === "in_progress"
      ? status.hint ?? "You're underway. Want to continue with the Strategist?"
      : "Start with the Strategist";

  const body = status.state === "in_progress" ? null : OPENING;

  return (
    <section
      className={cn(
        "flex flex-col gap-3 rounded-lg border bg-gradient-to-br from-primary/5 via-background to-background p-4",
        surface === "graph" ? "mx-4 mt-4" : "mb-4",
      )}
    >
      <header className="flex items-start gap-3">
        <div className="flex h-8 w-8 items-center justify-center rounded-full bg-primary/15 text-primary">
          <Compass className="h-4 w-4" />
        </div>
        <div className="min-w-0 flex-1">
          <p className="text-[10px] font-medium uppercase tracking-widest text-primary">
            Onboarding
          </p>
          <h2 className="mt-0.5 text-sm font-semibold">{adaptiveHeadline}</h2>
          {body ? (
            <p className="mt-1 text-xs leading-relaxed text-muted-foreground whitespace-pre-line">
              {body}
            </p>
          ) : null}
        </div>
      </header>

      <div className="flex flex-wrap gap-2">
        <Button size="sm" onClick={startConversation} disabled={busy}>
          <Sparkles className="mr-1 h-3.5 w-3.5" />
          {status.state === "in_progress" ? "Continue conversation" : "Start a conversation"}
        </Button>
        <Button
          size="sm"
          variant="outline"
          onClick={() => setIdentityOpen(true)}
          disabled={busy}
        >
          <User className="mr-1 h-3.5 w-3.5" />
          Tell agents about you
        </Button>
        {status.state === "pending" ? (
          <Button
            size="sm"
            variant="ghost"
            onClick={async () => {
              setBusy(true);
              try {
                await skip();
              } finally {
                setBusy(false);
              }
            }}
            disabled={busy}
          >
            Skip for now
          </Button>
        ) : null}
      </div>

      <IdentityBootstrapDialog
        open={identityOpen}
        onClose={() => setIdentityOpen(false)}
        onSeeded={(count) => {
          if (count > 0) {
            showToast(`Saved ${count} to your "You" scope.`);
          }
        }}
      />
    </section>
  );
}

function SkippedChip({
  hint,
  onResume,
  disabled,
}: {
  hint: string;
  onResume: () => void;
  disabled?: boolean;
}) {
  const [dismissed, setDismissed] = useState(false);
  if (dismissed) return null;

  return (
    <div className="flex items-center gap-2 rounded-md border bg-muted/20 px-3 py-1.5 text-[11px] text-muted-foreground">
      <Compass className="h-3 w-3" />
      <span>{hint}</span>
      <Button
        size="sm"
        variant="ghost"
        className="ml-auto h-6 text-[11px]"
        onClick={onResume}
        disabled={disabled}
      >
        Resume
      </Button>
      <button
        type="button"
        aria-label="Dismiss"
        onClick={() => setDismissed(true)}
        className="text-muted-foreground/60 hover:text-foreground"
      >
        <X className="h-3 w-3" />
      </button>
    </div>
  );
}
