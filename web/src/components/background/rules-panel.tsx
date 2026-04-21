import { useEffect, useState } from "react";
import { Plus, X } from "lucide-react";

import { api } from "@/lib/api";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import type { AgentRule } from "@/types";

type AgentId = "coherence" | "continuous_research";

const RULE_COLUMNS: Array<{
  type: AgentRule["rule_type"];
  label: string;
  placeholder: string;
}> = [
  { type: "mute_category", label: "Muted", placeholder: "Category to mute..." },
  { type: "ignore_pattern", label: "Ignored patterns", placeholder: "Substring to ignore..." },
  { type: "prioritize_category", label: "Prioritized", placeholder: "Category to prioritize..." },
];

export function RulesPanel({
  projectId,
  agentId,
}: {
  projectId: number;
  agentId: AgentId;
}) {
  const [rules, setRules] = useState<AgentRule[]>([]);

  useEffect(() => {
    api
      .listAgentRules(projectId, agentId)
      .then(setRules)
      .catch(() => setRules([]));
  }, [projectId, agentId]);

  async function add(type: AgentRule["rule_type"], value: string) {
    const trimmed = value.trim();
    if (!trimmed) return;
    const created = await api
      .createAgentRule(projectId, { agent_id: agentId, rule_type: type, value: trimmed })
      .catch(() => null);
    if (created) setRules((prev) => [...prev, created]);
  }

  async function remove(id: number) {
    await api.deleteAgentRule(projectId, id).catch(() => {});
    setRules((prev) => prev.filter((r) => r.id !== id));
  }

  return (
    <div className="rounded-lg border bg-card p-4">
      <div className="mb-3 flex items-baseline justify-between">
        <h2 className="text-sm font-semibold">Rules</h2>
        <p className="text-[10px] text-muted-foreground">
          Applied at detection time — existing findings are not affected.
        </p>
      </div>
      <div className="grid gap-4 md:grid-cols-3">
        {RULE_COLUMNS.map((col) => (
          <RuleColumn
            key={col.type}
            label={col.label}
            placeholder={col.placeholder}
            rules={rules.filter((r) => r.rule_type === col.type)}
            onAdd={(v) => add(col.type, v)}
            onRemove={remove}
          />
        ))}
      </div>
    </div>
  );
}

function RuleColumn({
  label,
  placeholder,
  rules,
  onAdd,
  onRemove,
}: {
  label: string;
  placeholder: string;
  rules: AgentRule[];
  onAdd: (value: string) => void;
  onRemove: (id: number) => void;
}) {
  const [value, setValue] = useState("");

  return (
    <div className="flex flex-col gap-2">
      <p className="text-[11px] font-medium uppercase tracking-widest text-muted-foreground">
        {label}
      </p>
      <form
        onSubmit={(e) => {
          e.preventDefault();
          onAdd(value);
          setValue("");
        }}
        className="flex items-center gap-1"
      >
        <Input
          value={value}
          placeholder={placeholder}
          onChange={(e) => setValue(e.target.value)}
          className="h-7 text-xs"
        />
        <Button type="submit" size="icon" variant="ghost" className="h-7 w-7">
          <Plus className="h-3.5 w-3.5" />
        </Button>
      </form>
      <div className="flex flex-col gap-1">
        {rules.length === 0 ? (
          <p className="text-[11px] text-muted-foreground/70">None</p>
        ) : (
          rules.map((rule) => (
            <div
              key={rule.id}
              className="flex items-center justify-between rounded-md border bg-background px-2 py-1"
            >
              <span className="truncate text-xs">{rule.value}</span>
              <Button
                size="icon"
                variant="ghost"
                className="h-5 w-5 shrink-0"
                onClick={() => onRemove(rule.id)}
              >
                <X className="h-3 w-3" />
              </Button>
            </div>
          ))
        )}
      </div>
    </div>
  );
}
