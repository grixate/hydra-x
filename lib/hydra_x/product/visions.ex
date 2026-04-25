defmodule HydraX.Product.Visions do
  @moduledoc """
  Context for the project-root Vision node. Backed by the substrate:
  visions are `Graph.Node` rows with `type_key: "vision"`. Uniqueness
  per project is enforced here (find-then-upsert).

  Per the Part 1 amendment, projects start blank. A project must have
  the "vision" type defined in its schema before `set_vision/2` can
  succeed — typically by applying a pretrained project that includes
  it. If the type isn't defined, the underlying `Node.changeset/2`
  rejects the write with `is not defined for this project`.
  """

  import Ecto.Query

  alias HydraX.Graph.Node, as: GraphNode
  alias HydraX.Graph.Nodes, as: GraphNodes
  alias HydraX.Product.Project
  alias HydraX.Repo

  def get_for_project(project_id) do
    project_id = to_int(project_id)

    Repo.one(
      from n in GraphNode,
        where: n.project_id == ^project_id and n.type_key == "vision",
        order_by: [desc: n.inserted_at],
        limit: 1
    )
  end

  @doc """
  Idempotent upsert. Creates the Vision node if none exists; updates
  body/title if one does. Keeps `project.description` in sync as a
  fallback view.
  """
  def set_vision(%Project{} = project, attrs) do
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)

    Repo.transaction(fn ->
      existing = get_for_project(project.id)

      result =
        case existing do
          nil ->
            GraphNodes.create_node(project.id, %{
              type_key: "vision",
              title: attrs["title"] || project.name || "Vision",
              body: attrs["body"],
              status: attrs["status"] || "active",
              attributes: attrs["metadata"] || %{}
            })

          %GraphNode{} = vision ->
            merged_attributes = Map.merge(vision.attributes || %{}, attrs["metadata"] || %{})

            GraphNodes.update_node(vision, %{
              title: attrs["title"] || vision.title,
              body: attrs["body"] || vision.body,
              status: attrs["status"] || vision.status,
              attributes: merged_attributes
            })
        end

      case result do
        {:ok, updated_vision} ->
          # Mirror body into project.description so the Why-button
          # fallback path still works for consumers that haven't switched
          # to Vision-as-node.
          project
          |> Ecto.Changeset.change(description: updated_vision.body)
          |> Repo.update!()

          updated_vision

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  def ensure_vision(%Project{} = project) do
    case get_for_project(project.id) do
      nil ->
        body = (project.description || "") |> String.trim()
        title = project.name || "Vision"

        attrs =
          if body == "",
            do: %{"title" => title, "body" => nil},
            else: %{"title" => title, "body" => body}

        case set_vision(project, attrs) do
          {:ok, vision} -> vision
          {:error, _} -> nil
        end

      %GraphNode{body: body} = vision when is_binary(body) and body != "" ->
        vision

      vision ->
        case String.trim(project.description || "") do
          "" ->
            vision

          body ->
            case set_vision(project, %{"body" => body}) do
              {:ok, updated} -> updated
              {:error, _} -> vision
            end
        end
    end
  end

  defp to_int(v) when is_integer(v), do: v
  defp to_int(v) when is_binary(v), do: String.to_integer(v)
end
