import { useCallback, useEffect, useState } from "react";
import { GitBranch, Cpu, Send, Loader2, Check } from "lucide-react";
import { api } from "@/lib/api";
import { cn } from "@/lib/utils";

type Branch = {
  id: number;
  branch_uuid: string;
  label: string;
  turn_count: number;
  inserted_at: string;
  active: boolean;
};

interface RuntimeControlsProps {
  projectId: number;
  conversationId: number;
  /** Controls whether the steering input is expected to succeed (i.e. agent
   *  is currently processing). When false, the steer button still attempts
   *  to send but the server returns 409. */
  isProcessing?: boolean;
  /** Called after any operation that changed the conversation's branch or
   *  model state, so the parent can refresh its own view. */
  onStateChange?: () => void;
}

export function RuntimeControls({
  projectId,
  conversationId,
  isProcessing = false,
  onStateChange,
}: RuntimeControlsProps) {
  const [branches, setBranches] = useState<Branch[]>([]);
  const [activeBranchUuid, setActiveBranchUuid] = useState<string | null>(null);
  const [availableModels, setAvailableModels] = useState<string[]>([]);
  const [currentModel, setCurrentModel] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const [steerText, setSteerText] = useState("");
  const [steerBusy, setSteerBusy] = useState(false);
  const [steerMsg, setSteerMsg] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const [bRes, mRes] = await Promise.all([
        api.listBranches(projectId, conversationId),
        api.listModels(projectId, conversationId),
      ]);
      setBranches(bRes.branches);
      setActiveBranchUuid(bRes.active_branch_uuid);
      setAvailableModels(mRes.available);
      setCurrentModel(mRes.current_override);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setLoading(false);
    }
  }, [projectId, conversationId]);

  useEffect(() => {
    refresh();
  }, [refresh]);

  const handleActivateBranch = async (branchUuid: string) => {
    try {
      await api.activateBranch(projectId, conversationId, branchUuid);
      await refresh();
      onStateChange?.();
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    }
  };

  const handleSwitchModel = async (model: string) => {
    const reason = window.prompt(
      `Why are you switching to ${model}?`,
      "explicit user request",
    );
    if (!reason) return;
    try {
      await api.switchModel(projectId, conversationId, { model, reason });
      await refresh();
      onStateChange?.();
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    }
  };

  const handleSteer = async () => {
    const content = steerText.trim();
    if (!content) return;
    setSteerBusy(true);
    setSteerMsg(null);
    try {
      await api.sendSteeringMessage(projectId, conversationId, content);
      setSteerText("");
      setSteerMsg("Steering message queued.");
      onStateChange?.();
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      setSteerMsg(msg);
    } finally {
      setSteerBusy(false);
    }
  };

  if (loading && branches.length === 0) {
    return (
      <div className="flex items-center gap-2 text-[11px] text-muted-foreground">
        <Loader2 className="h-3 w-3 animate-spin" /> Loading controls…
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-3 rounded-lg border bg-background/60 p-3 text-[12px]">
      {error && (
        <div className="rounded border border-red-300 bg-red-50 px-2 py-1 text-[11px] text-red-700">
          {error}
        </div>
      )}

      {/* --- Branches --- */}
      <section className="flex flex-col gap-1.5">
        <div className="flex items-center gap-1.5 text-[10px] font-semibold uppercase tracking-widest text-muted-foreground">
          <GitBranch className="h-3 w-3" /> Branches
        </div>
        <ul className="flex flex-col gap-1">
          {branches.map((b) => (
            <li key={b.branch_uuid}>
              <button
                type="button"
                onClick={() => !b.active && handleActivateBranch(b.branch_uuid)}
                disabled={b.active}
                className={cn(
                  "flex w-full items-center justify-between rounded px-2 py-1 text-left transition",
                  b.active
                    ? "bg-primary/10 text-primary"
                    : "hover:bg-muted cursor-pointer",
                )}
              >
                <span className="flex items-center gap-1.5">
                  {b.active && <Check className="h-3 w-3" />}
                  <span className="font-medium">{b.label}</span>
                </span>
                <span className="text-[10px] text-muted-foreground">
                  {b.turn_count} turns
                </span>
              </button>
            </li>
          ))}
          {branches.length === 0 && (
            <li className="px-2 py-1 text-[11px] text-muted-foreground">
              No branches yet — send a message first.
            </li>
          )}
        </ul>
      </section>

      {/* --- Model --- */}
      <section className="flex flex-col gap-1.5">
        <div className="flex items-center gap-1.5 text-[10px] font-semibold uppercase tracking-widest text-muted-foreground">
          <Cpu className="h-3 w-3" /> Model
          {currentModel && (
            <span className="ml-auto rounded bg-primary/10 px-1.5 py-0.5 text-[10px] font-normal normal-case text-primary">
              override: {currentModel}
            </span>
          )}
        </div>
        <select
          className="w-full rounded border bg-background px-2 py-1 text-[11px]"
          value={currentModel ?? ""}
          onChange={(e) => e.target.value && handleSwitchModel(e.target.value)}
        >
          <option value="">— default —</option>
          {availableModels.map((m) => (
            <option key={m} value={m}>
              {m}
            </option>
          ))}
        </select>
      </section>

      {/* --- Steering --- */}
      <section className="flex flex-col gap-1.5">
        <div className="flex items-center gap-1.5 text-[10px] font-semibold uppercase tracking-widest text-muted-foreground">
          <Send className="h-3 w-3" /> Steering
          {isProcessing && (
            <span className="ml-auto flex items-center gap-1 text-[10px] font-normal normal-case text-muted-foreground">
              <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-green-500" />
              processing
            </span>
          )}
        </div>
        <textarea
          value={steerText}
          onChange={(e) => setSteerText(e.target.value)}
          placeholder={
            isProcessing
              ? "Send a course-correction now (delivered after current step)…"
              : "Only valid while the agent is processing."
          }
          rows={2}
          className="w-full rounded border bg-background px-2 py-1 text-[11px] resize-none"
          disabled={!isProcessing || steerBusy}
        />
        <div className="flex items-center justify-between">
          <button
            type="button"
            onClick={handleSteer}
            disabled={!isProcessing || !steerText.trim() || steerBusy}
            className={cn(
              "rounded px-3 py-1 text-[11px] font-medium transition",
              isProcessing && steerText.trim() && !steerBusy
                ? "bg-primary text-primary-foreground hover:opacity-90"
                : "bg-muted text-muted-foreground cursor-not-allowed",
            )}
          >
            {steerBusy ? (
              <span className="inline-flex items-center gap-1">
                <Loader2 className="h-3 w-3 animate-spin" /> Sending…
              </span>
            ) : (
              "Send steering"
            )}
          </button>
          {steerMsg && (
            <span className="text-[10px] text-muted-foreground">{steerMsg}</span>
          )}
        </div>
      </section>
    </div>
  );
}
