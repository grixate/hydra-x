defmodule HydraX.Product.ContinuousResearch do
  @moduledoc """
  Autonomous agent that monitors external sources (competitors, market, configured
  keywords) and creates signal nodes in the product graph when it finds relevant changes.
  """

  import Ecto.Query

  alias HydraX.Product.PubSub, as: ProductPubSub
  alias HydraX.Product.WatchTarget
  alias HydraX.Repo

  # -------------------------------------------------------------------
  # Configuration
  # -------------------------------------------------------------------

  def add_watch_target(project_or_id, attrs) do
    project_id = project_id(project_or_id)

    attrs =
      attrs
      |> HydraX.Runtime.Helpers.normalize_string_keys()
      |> Map.put("project_id", project_id)

    %WatchTarget{}
    |> WatchTarget.changeset(attrs)
    |> Repo.insert()
  end

  def remove_watch_target(target_id) do
    target = Repo.get!(WatchTarget, target_id)
    Repo.delete(target)
  end

  def list_watch_targets(project_or_id) do
    project_id = project_id(project_or_id)

    WatchTarget
    |> where([t], t.project_id == ^project_id)
    |> order_by([t], desc: t.inserted_at)
    |> Repo.all()
  end

  # -------------------------------------------------------------------
  # Execution (called by scheduler)
  # -------------------------------------------------------------------

  def check_targets(project_id) do
    now = DateTime.utc_now()

    targets =
      WatchTarget
      |> where([t], t.project_id == ^project_id and t.status == "active")
      |> Repo.all()
      |> Enum.filter(&target_due?(&1, now))

    results =
      Enum.map(targets, fn target ->
        result = check_single_target(target)

        target
        |> WatchTarget.changeset(%{"last_checked_at" => now})
        |> Repo.update()

        result
      end)

    {:ok, %{checked: length(targets), results: results}}
  end

  def assess_relevance(_project_id, _finding_text) do
    # Placeholder for LLM-based relevance assessment.
    # Will use project strategy context when LLM integration is wired in.
    {:relevant, "Relevance assessment pending LLM integration"}
  end

  # -------------------------------------------------------------------
  # Private
  # -------------------------------------------------------------------

  defp target_due?(%WatchTarget{last_checked_at: nil}, _now), do: true

  defp target_due?(%WatchTarget{last_checked_at: last, check_interval_hours: hours}, now) do
    DateTime.diff(now, last, :hour) >= hours
  end

  defp check_single_target(%WatchTarget{} = target) do
    # Placeholder — will use WebSearch/HttpFetch tools when fully wired.
    # For now, returns a stub result.
    %{
      target_id: target.id,
      target_type: target.target_type,
      value: target.value,
      status: :checked,
      findings: []
    }
  end

  defp project_id(%{id: id}), do: id
  defp project_id(id) when is_integer(id), do: id
  defp project_id(id) when is_binary(id), do: String.to_integer(id)
end
