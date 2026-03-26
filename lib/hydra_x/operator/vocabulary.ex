defmodule HydraX.Operator.Vocabulary do
  @moduledoc """
  Canonical operator-facing labels for runtime state concepts.

  Every operator surface (report, CLI, LiveView) should use these functions
  instead of inline strings to ensure the same runtime state reads consistently
  across all inspection surfaces.
  """

  # Claims: standardize on "stale" for timed-out claims
  def claim_label(:stale), do: "stale"
  def claim_label(:active), do: "active"
  def claim_label(:remote), do: "remote"
  def claim_label(_), do: "unknown"

  # Intervention types
  def intervention_label(:selected), do: "selected"
  def intervention_label(:fallback), do: "fallback"
  def intervention_label(:operator_guided), do: "operator-guided"
  def intervention_label(:review_guided), do: "review-guided"
  def intervention_label(:request_review), do: "review-requested"
  def intervention_label(:total), do: "intervention"
  def intervention_label(_), do: "unknown"

  # Recovery: standardize "fallback" over "alternative"
  def recovery_label(:selected), do: "selected"
  def recovery_label(:fallback), do: "fallback"
  def recovery_label(:deescalated), do: "de-escalated"
  def recovery_label(_), do: "unknown"

  # Ownership
  def ownership_label(:local), do: "local"
  def ownership_label(:remote), do: "remote"
  def ownership_label(:orphaned), do: "orphaned"
  def ownership_label(:unclaimed), do: "unclaimed"
  def ownership_label(_), do: "unknown"

  # Posture
  def posture_label(:single_node), do: "local single-node"
  def posture_label(:multi_node), do: "production multi-node"
  def posture_label(:compatible), do: "compatible"
  def posture_label(:degraded), do: "degraded"
  def posture_label(:incompatible), do: "incompatible"
  def posture_label(:stable), do: "stable"
  def posture_label(:canary), do: "canary"
  def posture_label(:staged), do: "staged"
  def posture_label(:healthy), do: "healthy"
  def posture_label(:balanced), do: "balanced"
  def posture_label(:skewed), do: "skewed"
  def posture_label(:starved), do: "starved"
  def posture_label(_), do: "unknown"

  # Capability risk
  def risk_label(:low), do: "low"
  def risk_label(:medium), do: "medium"
  def risk_label(:high), do: "high"
  def risk_label(_), do: "unknown"

  # Rollout state
  def rollout_label(:stable), do: "stable"
  def rollout_label(:canary), do: "canary"
  def rollout_label(:staged), do: "staged"
  def rollout_label(:disabled), do: "disabled"
  def rollout_label(_), do: "unknown"
end
