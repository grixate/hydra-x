defmodule HydraX.SharedMemory do
  @moduledoc """
  Context for the shared-memory (per-user "You") scope.

  Stream A delivers the data layer only; UI surfaces, Memory-agent
  distillation, and cross-project context injection come in Stream C
  per `shared-memory-spec.md` §9.
  """

  import Ecto.Query

  alias HydraX.Accounts.SharedScope
  alias HydraX.Repo
  alias HydraX.SharedMemory.Distillation
  alias HydraX.SharedMemory.Node

  ## Scope helpers

  def get_scope_for_user(user_id), do: Repo.get_by(SharedScope, owner_user_id: user_id)

  def ensure_scope_for_user(user_id) do
    case get_scope_for_user(user_id) do
      %SharedScope{} = s ->
        {:ok, s}

      nil ->
        %SharedScope{}
        |> SharedScope.changeset(%{owner_user_id: user_id, display_name: "You"})
        |> Repo.insert()
    end
  end

  ## Node helpers

  def list_nodes(scope_id, opts \\ []) do
    node_type = opts[:node_type]
    status = Keyword.get(opts, :status, "active")

    Node
    |> where([n], n.shared_scope_id == ^scope_id and n.status == ^status)
    |> apply_type_filter(node_type)
    |> order_by([n], desc: n.last_referenced_at, desc: n.inserted_at)
    |> Repo.all()
  end

  defp apply_type_filter(query, nil), do: query
  defp apply_type_filter(query, type), do: where(query, [n], n.node_type == ^type)

  def create_node(%SharedScope{id: scope_id}, attrs) do
    attrs =
      attrs
      |> Map.new(fn {k, v} -> {to_string(k), v} end)
      |> Map.put("shared_scope_id", scope_id)

    %Node{} |> Node.changeset(attrs) |> Repo.insert()
  end

  def mark_referenced(%Node{} = node) do
    node
    |> Ecto.Changeset.change(last_referenced_at: DateTime.utc_now())
    |> Repo.update()
  end

  ## Distillation helpers

  def link_distillation(%Node{id: node_id}, attrs) do
    attrs =
      attrs
      |> Map.new(fn {k, v} -> {to_string(k), v} end)
      |> Map.put("shared_node_id", node_id)

    %Distillation{}
    |> Distillation.changeset(attrs)
    |> Repo.insert(
      on_conflict: :nothing,
      conflict_target: [:shared_node_id, :episode_node_type, :episode_node_id]
    )
  end

  def list_distillations(%Node{id: node_id}) do
    Distillation
    |> where([d], d.shared_node_id == ^node_id)
    |> order_by([d], desc: d.weight, desc: d.inserted_at)
    |> Repo.all()
  end
end
