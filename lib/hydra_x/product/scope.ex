defmodule HydraX.Product.Scope do
  @moduledoc """
  Shared helpers for the `scope` / `scope_root_id` fields added to every
  project-node schema per the Shared Memory spec (§9, Cycle 1).

  In Cycle 1 every node is implicitly project-scoped. `scope_root_id` simply
  echoes `project_id`. Cycle 2 will introduce `scope = "shared"` pointing at a
  `SharedScope` entity; these helpers will still apply.
  """

  import Ecto.Changeset

  @scopes ~w(project shared)

  def scopes, do: @scopes

  @doc """
  Call after `cast/3` on any node changeset. Fills `scope_root_id` from
  `project_id` if not set, and validates `scope` is in the allowed set.
  """
  def validate_and_default(changeset) do
    changeset
    |> put_default_scope_root()
    |> validate_inclusion(:scope, @scopes)
  end

  defp put_default_scope_root(changeset) do
    case get_field(changeset, :scope_root_id) do
      nil ->
        case get_field(changeset, :project_id) do
          nil -> changeset
          pid -> put_change(changeset, :scope_root_id, pid)
        end

      _ ->
        changeset
    end
  end
end
