defmodule HydraX.Tools.SkillLoad do
  @behaviour HydraX.Tool

  alias HydraX.Runtime.Skills

  @max_excerpt 16_000

  @impl true
  def name, do: "skill_load"

  @impl true
  def description,
    do: "Load the full body of an enabled skill by slug. Use when the compact skill index mentions a skill you need to read in detail."

  @impl true
  def safety_classification, do: "skill_read"

  @impl true
  def tool_schema do
    %{
      name: "skill_load",
      description:
        "Fetch the full markdown body of a workspace skill by its slug. The slug comes from the skill index in the system prompt or from skill_inspect. Returns the file content so you can follow the skill's instructions.",
      input_schema: %{
        type: "object",
        properties: %{
          slug: %{
            type: "string",
            description: "The skill slug, e.g. \"postgres-conventions\""
          }
        },
        required: ["slug"]
      }
    }
  end

  @impl true
  def execute(params, _context) do
    agent_id = params[:agent_id] || params["agent_id"]
    slug = params[:slug] || params["slug"]

    cond do
      not is_integer(agent_id) ->
        {:error, :missing_agent_id}

      not (is_binary(slug) and slug != "") ->
        {:error, :missing_slug}

      true ->
        case Skills.load_skill_body(agent_id, slug) do
          {:ok, %{slug: slug, name: name, path: path, content: content}} ->
            excerpt = String.slice(content, 0, @max_excerpt)

            {:ok,
             %{
               slug: slug,
               name: name,
               path: path,
               content: excerpt,
               truncated: byte_size(excerpt) < byte_size(content),
               size: byte_size(content)
             }}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @impl true
  def result_summary(%{slug: slug, size: size}), do: "loaded skill #{slug} (#{size}b)"
  def result_summary(%{error: error}) when is_binary(error), do: error
  def result_summary(payload), do: inspect(payload, limit: 8, printable_limit: 120)
end
