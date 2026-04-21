defmodule HydraX.Product.WorkspaceEvent do
  @moduledoc """
  Audit row recording a single workspace operation: read, write, edit, list,
  exec, etc. Persisted by `HydraX.Product.WorkspaceEvents.log/1`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @kinds ~w(read write edit list search exec test ensure_root destroy)
  @outcomes ~w(ok error)

  schema "hx_workspace_events" do
    field :kind, :string
    field :path, :string
    field :command, :map
    field :exit_code, :integer
    field :outcome, :string
    field :error, :string
    field :metadata, :map, default: %{}

    belongs_to :workspace, HydraX.Product.Workspace
    belongs_to :project, HydraX.Product.Project

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :workspace_id,
      :project_id,
      :kind,
      :path,
      :command,
      :exit_code,
      :outcome,
      :error,
      :metadata
    ])
    |> validate_required([:workspace_id, :project_id, :kind, :outcome])
    |> validate_inclusion(:kind, @kinds)
    |> validate_inclusion(:outcome, @outcomes)
  end

  def kinds, do: @kinds
end
