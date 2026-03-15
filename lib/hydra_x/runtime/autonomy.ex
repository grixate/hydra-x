defmodule HydraX.Runtime.Autonomy do
  @moduledoc """
  Role, capability, and work-item defaults for Hydra's autonomy runtime.
  """

  alias HydraX.Runtime.Helpers

  @roles ~w(planner researcher builder reviewer operator designer trader)
  @autonomy_levels ~w(observe recommend execute_with_review execute_with_promotion fully_automatic)
  @side_effect_classes ~w(read_only external_delivery repo_write plugin_install financial_action)

  def roles, do: @roles
  def autonomy_levels, do: @autonomy_levels
  def side_effect_classes, do: @side_effect_classes

  def role_options do
    Enum.map(@roles, fn role -> {String.capitalize(role), role} end)
  end

  def default_role, do: "operator"

  def role_for_kind(kind) do
    case normalize_kind(kind) do
      "research" -> "researcher"
      "engineering" -> "builder"
      "extension" -> "builder"
      "review" -> "reviewer"
      "plan" -> "planner"
      "design" -> "designer"
      "trading" -> "trader"
      _ -> "operator"
    end
  end

  def ensure_capability_profile(role, profile \\ %{}) do
    role = normalize_role(role)
    defaults = default_capability_profile(role)
    overrides = Helpers.normalize_string_keys(profile || %{})

    Map.merge(defaults, overrides, fn _key, left, right ->
      merge_capability_value(left, right)
    end)
  end

  def default_capability_profile(role) do
    role = normalize_role(role)

    base = %{
      "role" => role,
      "tools" => [],
      "mcp_actions" => [],
      "skill_manifests" => [],
      "delivery_modes" => ["report"],
      "memory_scope" => ["global_agent_memory"],
      "artifact_types" => ["note"],
      "side_effect_classes" => ["read_only"],
      "max_autonomy_level" => "recommend"
    }

    case role do
      "planner" ->
        Map.merge(base, %{
          "tools" => ["memory_recall", "skill_inspect", "mcp_catalog"],
          "artifact_types" => ["plan", "decision_ledger"],
          "memory_scope" => ["global_agent_memory", "role_memory", "artifact_derived_memory"],
          "delivery_modes" => ["report", "control_plane"],
          "max_autonomy_level" => "execute_with_review"
        })

      "researcher" ->
        Map.merge(base, %{
          "tools" => ["memory_recall", "web_search", "http_fetch", "browser_automation"],
          "artifact_types" => ["research_report", "plan", "source_snapshot"],
          "memory_scope" => ["global_agent_memory", "work_item_scratch_memory"],
          "delivery_modes" => ["report", "channel"],
          "max_autonomy_level" => "execute_with_review"
        })

      "builder" ->
        Map.merge(base, %{
          "tools" => [
            "memory_recall",
            "workspace_list",
            "workspace_read",
            "workspace_write",
            "workspace_patch",
            "shell_command"
          ],
          "artifact_types" => ["code_change_set", "proposal", "patch_bundle"],
          "memory_scope" => ["global_agent_memory", "role_memory", "work_item_scratch_memory"],
          "side_effect_classes" => ["read_only", "repo_write", "plugin_install"],
          "delivery_modes" => ["report", "control_plane"],
          "max_autonomy_level" => "execute_with_promotion"
        })

      "reviewer" ->
        Map.merge(base, %{
          "tools" => ["memory_recall", "workspace_read", "shell_command"],
          "artifact_types" => ["review_report", "decision_ledger"],
          "memory_scope" => ["global_agent_memory", "artifact_derived_memory"],
          "delivery_modes" => ["report", "control_plane"],
          "max_autonomy_level" => "execute_with_review"
        })

      "designer" ->
        Map.merge(base, %{
          "tools" => ["memory_recall", "browser_automation"],
          "artifact_types" => ["design_spec", "screenshot", "plan"],
          "memory_scope" => ["global_agent_memory", "artifact_derived_memory"],
          "delivery_modes" => ["report", "channel"],
          "max_autonomy_level" => "execute_with_review"
        })

      "trader" ->
        Map.merge(base, %{
          "tools" => ["memory_recall", "web_search", "http_fetch"],
          "artifact_types" => ["trading_brief", "decision_ledger"],
          "memory_scope" => ["global_agent_memory", "role_memory"],
          "side_effect_classes" => ["read_only", "financial_action"],
          "delivery_modes" => ["report"],
          "max_autonomy_level" => "observe"
        })

      _ ->
        Map.merge(base, %{
          "tools" => ["memory_recall", "skill_inspect", "mcp_catalog"],
          "artifact_types" => ["note", "decision_ledger"],
          "memory_scope" => ["global_agent_memory", "artifact_derived_memory"],
          "delivery_modes" => ["report", "control_plane"],
          "max_autonomy_level" => "execute_with_review"
        })
    end
  end

  def capability_summary(profile) when is_map(profile) do
    %{
      tools: Enum.take(List.wrap(profile["tools"]), 4),
      artifact_types: Enum.take(List.wrap(profile["artifact_types"]), 4),
      delivery_modes: List.wrap(profile["delivery_modes"]),
      max_autonomy_level: profile["max_autonomy_level"],
      side_effect_classes: List.wrap(profile["side_effect_classes"])
    }
  end

  def side_effect_allowed?(profile, class) when is_map(profile) and is_binary(class) do
    class in List.wrap(profile["side_effect_classes"])
  end

  def normalize_role(role) when role in @roles, do: role
  def normalize_role(role) when is_binary(role) and role in @roles, do: role
  def normalize_role(_role), do: default_role()

  def normalize_kind(kind) when is_binary(kind), do: kind
  def normalize_kind(_kind), do: "task"

  defp merge_capability_value(left, right) when is_list(left) and is_list(right) do
    Enum.uniq(left ++ right)
  end

  defp merge_capability_value(_left, right), do: right
end
