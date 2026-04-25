defmodule HydraX.Product.Tools.ProjectContextUpdate do
  @behaviour HydraX.Tool

  alias HydraX.Product
  alias HydraX.Product.OnboardingTriggers

  @impl true
  def name, do: "project_context_update"

  @impl true
  def description,
    do:
      "Store extracted product context (domain, users, competitors, assumptions) into the project. " <>
        "Call this as you learn key facts about the product during conversation. " <>
        "This enables other agents to start working autonomously."

  @impl true
  def safety_classification, do: "product_write"

  @impl true
  def tool_schema do
    %{
      name: "project_context_update",
      description:
        "Store extracted product context into project metadata. Call this when you learn " <>
          "key facts about the product, target users, competitors, or business model. " <>
          "This triggers autonomous work by other agents.",
      input_schema: %{
        type: "object",
        properties: %{
          product_domain: %{
            type: "string",
            description: "The product category or industry (e.g. 'project management', 'fintech')"
          },
          target_users: %{
            type: "string",
            description: "Who the product is for (e.g. 'solo founders', 'enterprise teams')"
          },
          competitors: %{
            type: "array",
            items: %{type: "string"},
            description: "Competitor names or products"
          },
          key_assumptions: %{
            type: "array",
            items: %{type: "string"},
            description: "Key hypotheses or assumptions to test"
          },
          business_model: %{
            type: "string",
            description: "How the product makes money (e.g. 'freemium', 'subscription')"
          },
          stage: %{
            type: "string",
            enum: ["idea", "validation", "building", "launched", "scaling"],
            description: "Current product stage"
          }
        },
        required: []
      }
    }
  end

  @impl true
  def execute(params, _context) do
    with {:ok, project_id} <- extract_project_id(params),
         {:ok, project} <- fetch_project(project_id) do
      existing_meta = project.metadata || %{}

      # Build the update map from non-nil params
      updates =
        %{}
        |> maybe_put("product_domain", params[:product_domain] || params["product_domain"])
        |> maybe_put("target_users", params[:target_users] || params["target_users"])
        |> maybe_put(
          "competitors",
          merge_list(existing_meta["competitors"], params[:competitors] || params["competitors"])
        )
        |> maybe_put(
          "key_assumptions",
          merge_list(
            existing_meta["key_assumptions"],
            params[:key_assumptions] || params["key_assumptions"]
          )
        )
        |> maybe_put("business_model", params[:business_model] || params["business_model"])
        |> maybe_put("stage", params[:stage] || params["stage"])

      new_meta = Map.merge(existing_meta, updates)

      case Product.update_project(project, %{"metadata" => new_meta}) do
        {:ok, updated_project} ->
          updated_fields = Map.keys(updates)

          # Trigger onboarding side-effects asynchronously
          Task.start(fn ->
            OnboardingTriggers.maybe_trigger(updated_project, updated_fields)
          end)

          {:ok,
           %{updated_fields: updated_fields, context_complete: has_enough_context?(new_meta)}}

        {:error, changeset} ->
          {:error, %{error: "update_failed", details: inspect(changeset.errors)}}
      end
    end
  end

  @impl true
  def result_summary(%{updated_fields: fields, context_complete: true}),
    do:
      "Updated project context (#{Enum.join(fields, ", ")}). Enough context for autonomous work."

  def result_summary(%{updated_fields: fields}),
    do: "Updated project context: #{Enum.join(fields, ", ")}"

  def result_summary(other), do: inspect(other, limit: 8)

  defp extract_project_id(params) do
    case params[:project_id] || params["project_id"] do
      value when is_integer(value) ->
        {:ok, value}

      value when is_binary(value) ->
        case Integer.parse(value) do
          {integer, ""} -> {:ok, integer}
          _ -> {:error, :product_project_context_required}
        end

      _ ->
        {:error, :product_project_context_required}
    end
  end

  defp fetch_project(project_id) do
    {:ok, Product.get_project!(project_id)}
  rescue
    Ecto.NoResultsError -> {:error, %{error: "project_not_found"}}
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, []), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp merge_list(nil, new) when is_list(new), do: new
  defp merge_list(existing, nil), do: existing

  defp merge_list(existing, new) when is_list(existing) and is_list(new) do
    Enum.uniq(existing ++ new)
  end

  defp merge_list(_, new), do: new

  defp has_enough_context?(meta) do
    is_binary(meta["product_domain"]) and meta["product_domain"] != "" and
      is_binary(meta["target_users"]) and meta["target_users"] != ""
  end
end
