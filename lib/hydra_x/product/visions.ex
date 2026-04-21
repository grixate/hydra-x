defmodule HydraX.Product.Visions do
  @moduledoc """
  Context for the project-root Vision node.
  """

  alias HydraX.Repo
  alias HydraX.Product.Project
  alias HydraX.Product.Vision

  def get_for_project(project_id) do
    Repo.get_by(Vision, project_id: to_int(project_id))
  end

  @doc """
  Idempotent upsert. Creates the Vision if none exists; updates body/title
  if one does. Keeps `project.description` in sync as a fallback view.
  """
  def set_vision(%Project{} = project, attrs) do
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)

    Repo.transaction(fn ->
      vision =
        case get_for_project(project.id) do
          nil -> %Vision{project_id: project.id}
          existing -> existing
        end

      merged = %{
        "project_id" => project.id,
        "title" => attrs["title"] || vision.title || project.name,
        "body" => attrs["body"] || vision.body,
        "status" => attrs["status"] || vision.status || "active",
        "metadata" => Map.merge(vision.metadata || %{}, attrs["metadata"] || %{})
      }

      {:ok, updated_vision} = vision |> Vision.changeset(merged) |> Repo.insert_or_update()

      # Mirror into project.description so the Why-button fallback path
      # still works until every consumer has switched to Vision-as-node.
      project
      |> Ecto.Changeset.change(description: updated_vision.body)
      |> Repo.update!()

      updated_vision
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

        {:ok, vision} = set_vision(project, attrs)
        vision

      %Vision{body: body} = vision when is_binary(body) and body != "" ->
        vision

      vision ->
        # Vision row exists but body is empty. If `project.description`
        # has content, mirror it in so `vision_set?` returns a consistent
        # answer (bug fix — previously onboarding could complete with an
        # empty Vision node but a non-empty description).
        case String.trim(project.description || "") do
          "" ->
            vision

          body ->
            {:ok, updated} = set_vision(project, %{"body" => body})
            updated
        end
    end
  end

  defp to_int(v) when is_integer(v), do: v
  defp to_int(v) when is_binary(v), do: String.to_integer(v)
end
