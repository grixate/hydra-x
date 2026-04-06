defmodule HydraX.Product.Tools.KnowledgePropose do
  @behaviour HydraX.Tool

  alias HydraX.Product

  @impl true
  def name, do: "knowledge_propose"

  @impl true
  def description,
    do: "Propose a new knowledge entry based on a pattern observed in your work"

  @impl true
  def safety_classification, do: "product_write"

  @impl true
  def tool_schema do
    %{
      name: "knowledge_propose",
      description:
        "Propose a new knowledge entry based on a pattern you've observed in your work. " <>
        "Knowledge entries become part of your permanent context, helping you handle " <>
        "similar situations better in the future. The entry will be reviewed by the user " <>
        "before becoming active.",
      input_schema: %{
        type: "object",
        properties: %{
          title: %{type: "string", description: "Descriptive title for this knowledge entry"},
          content: %{
            type: "string",
            description:
              "The knowledge content (markdown). Include: the pattern, when to apply it, examples, and caveats."
          },
          entry_type: %{
            type: "string",
            enum: [
              "coding_conventions", "design_language", "process_rules",
              "domain_knowledge", "pattern", "custom"
            ],
            description: "Type of knowledge entry"
          },
          rationale: %{
            type: "string",
            description: "Why this knowledge should be codified. What pattern prompted this?"
          }
        },
        required: ["title", "content", "entry_type", "rationale"]
      }
    }
  end

  @impl true
  def execute(params, _context) do
    with {:ok, project_id} <- project_id(params),
         persona = params["product_persona"] || "system",
         attrs = %{
           "title" => params["title"],
           "content" => params["content"],
           "entry_type" => params["entry_type"],
           "assigned_personas" => [persona],
           "metadata" => %{"rationale" => params["rationale"]}
         },
         {:ok, entry} <- Product.propose_knowledge(project_id, attrs) do
      {:ok,
       %{
         knowledge_entry: %{
           id: entry.id,
           title: entry.title,
           status: entry.status,
           entry_type: entry.entry_type
         }
       }}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, %{error: "validation_failed", details: translate_errors(changeset)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def result_summary(%{knowledge_entry: entry}),
    do: "proposed knowledge entry #{entry.id}: #{entry.title} (#{entry.status})"

  def result_summary(%{error: error}) when is_binary(error), do: error
  def result_summary(payload), do: inspect(payload, limit: 8, printable_limit: 120)

  defp project_id(params) do
    case params[:project_id] || params["project_id"] do
      value when is_integer(value) -> {:ok, value}
      value when is_binary(value) ->
        case Integer.parse(value) do
          {integer, ""} -> {:ok, integer}
          _ -> {:error, :product_project_context_required}
        end
      _ -> {:error, :product_project_context_required}
    end
  end

  defp translate_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
