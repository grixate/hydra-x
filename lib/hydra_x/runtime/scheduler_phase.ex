defmodule HydraX.Runtime.SchedulerPhase do
  @moduledoc false

  @phases ~w(
    pending_ingress stale_claim_cleanup assignment_recovery
    role_queue_dispatch work_item_replay ownership_handoff
    deferred_delivery delegation_expansion deferred_cooldown
  )a

  @phase_labels %{
    pending_ingress: "Ingress processing",
    stale_claim_cleanup: "Stale claim cleanup",
    assignment_recovery: "Assignment recovery",
    role_queue_dispatch: "Role queue dispatch",
    work_item_replay: "Work item replay",
    ownership_handoff: "Ownership handoff",
    deferred_delivery: "Deferred delivery",
    delegation_expansion: "Delegation expansion",
    deferred_cooldown: "Deferred cooldown"
  }

  def phases, do: @phases
  def label(phase), do: Map.get(@phase_labels, phase, to_string(phase))

  def pass_result(phase, owner, counts) do
    %{
      phase: phase,
      owner: owner,
      processed_count: counts[:processed] || 0,
      skipped_count: counts[:skipped] || 0,
      error_count: counts[:errored] || 0,
      deferred_count: counts[:deferred] || 0,
      remote_owned_count: counts[:remote_owned] || 0
    }
  end
end
