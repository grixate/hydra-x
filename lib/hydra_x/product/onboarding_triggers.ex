defmodule HydraX.Product.OnboardingTriggers do
  @moduledoc """
  Side-effects triggered when the Strategist calls project_context_update
  during onboarding. Creates watch targets, triggers researcher sweep,
  and schedules initiative engine activation.
  """

  require Logger

  alias HydraX.Product
  alias HydraX.Product.AgentBridge
  alias HydraX.Product.ContinuousResearch

  @doc """
  Evaluate which triggers to fire based on which fields were updated.
  Called asynchronously from the project_context_update tool.
  """
  def maybe_trigger(project, updated_fields) do
    meta = project.metadata || %{}

    if "competitors" in updated_fields do
      create_competitor_watch_targets(project)
    end

    # Only fire sweep/initiative triggers once (guard with a metadata flag)
    already_triggered? = meta["onboarding_sweep_triggered"] == true

    if has_enough_context?(project) and not already_triggered? do
      # Mark as triggered to prevent duplicate sweeps
      Product.update_project(project, %{
        "metadata" => Map.put(meta, "onboarding_sweep_triggered", true)
      })

      create_domain_watch_targets(project)
      trigger_initial_researcher_sweep(project)
      schedule_initiative_activation(project)
    end
  rescue
    error ->
      Logger.error(
        "[OnboardingTriggers] Error in triggers for project #{project.id}: #{inspect(error)}"
      )
  end

  # -------------------------------------------------------------------
  # Watch target creation
  # -------------------------------------------------------------------

  defp create_competitor_watch_targets(project) do
    competitors = get_in(project.metadata || %{}, ["competitors"]) || []

    Enum.each(competitors, fn name ->
      case ContinuousResearch.add_watch_target(project.id, %{
             "target_type" => "competitor",
             "value" => name,
             "check_interval_hours" => 24
           }) do
        {:ok, _} ->
          Logger.info("[OnboardingTriggers] Created competitor watch target: #{name}")

        {:error, _} ->
          :ok
      end
    end)
  end

  defp create_domain_watch_targets(project) do
    meta = project.metadata || %{}
    domain = meta["product_domain"]
    target_users = meta["target_users"]

    if domain do
      ContinuousResearch.add_watch_target(project.id, %{
        "target_type" => "keyword",
        "value" => domain,
        "check_interval_hours" => 48
      })
    end

    if target_users do
      ContinuousResearch.add_watch_target(project.id, %{
        "target_type" => "keyword",
        "value" => "#{target_users} tools",
        "check_interval_hours" => 48
      })
    end
  end

  # -------------------------------------------------------------------
  # Researcher initial sweep
  # -------------------------------------------------------------------

  defp trigger_initial_researcher_sweep(project) do
    meta = project.metadata || %{}
    domain = meta["product_domain"]
    target_users = meta["target_users"]
    competitors = meta["competitors"] || []

    prompt = build_sweep_prompt(domain, target_users, competitors)

    case AgentBridge.ensure_project_conversation(project.id, "researcher", %{
           "channel" => "autonomous",
           "external_ref" => "initial_sweep_#{project.id}",
           "title" => "Initial research sweep",
           "metadata" => %{"source" => "onboarding_trigger"}
         }) do
      {:ok, conversation} ->
        AgentBridge.submit_message(conversation, prompt, %{
          "autonomous" => true,
          "initiative_source" => true
        })

      _ ->
        :ok
    end
  end

  defp build_sweep_prompt(domain, target_users, competitors) do
    parts = [
      "Run an initial research sweep for a new project. Search for and create insights from:",
      if(domain, do: "- Market overview: #{domain} market size, trends, and landscape"),
      if(target_users,
        do: "- User research: #{target_users} pain points, workflows, and tool usage"
      ),
      if(competitors != [],
        do:
          "- Competitive analysis: " <>
            Enum.join(competitors, ", ") <> " — pricing, features, positioning"
      ),
      if(domain, do: "- Industry studies: recent research on #{domain}"),
      "",
      "Create draft insights for each significant finding. Focus on actionable intelligence."
    ]

    parts |> Enum.reject(&is_nil/1) |> Enum.join("\n")
  end

  # -------------------------------------------------------------------
  # Initiative engine scheduling
  # -------------------------------------------------------------------

  defp schedule_initiative_activation(project) do
    # Delay initiative start by 15 minutes to let onboarding conversation complete
    spawn(fn ->
      Process.sleep(:timer.minutes(15))

      try do
        Product.start_initiative_engine(project.id)
        Logger.info("[OnboardingTriggers] Initiative engine activated for project #{project.id}")
      rescue
        _ -> :ok
      end
    end)
  end

  defp has_enough_context?(project) do
    meta = project.metadata || %{}

    is_binary(meta["product_domain"]) and meta["product_domain"] != "" and
      is_binary(meta["target_users"]) and meta["target_users"] != ""
  end
end
