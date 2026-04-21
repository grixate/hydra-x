defmodule HydraX.Product.Workspace do
  @moduledoc """
  Per-project filesystem workspace where a coding agent can read, write, and
  execute commands. Backed by `HydraX.Product.Workspace.Backend` (host or
  docker). One workspace per project.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @sandbox_modes ~w(host docker)
  @statuses ~w(provisioning ready stopped error)

  schema "hx_product_workspaces" do
    field :fs_path, :string
    field :sandbox_mode, :string, default: "host"
    field :container_id, :string
    field :status, :string, default: "provisioning"
    field :git_origin, :string
    field :last_used_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    belongs_to :project, HydraX.Product.Project

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(workspace, attrs) do
    workspace
    |> cast(attrs, [
      :project_id,
      :fs_path,
      :sandbox_mode,
      :container_id,
      :status,
      :git_origin,
      :last_used_at,
      :metadata
    ])
    |> validate_required([:project_id, :fs_path, :sandbox_mode, :status])
    |> validate_inclusion(:sandbox_mode, @sandbox_modes)
    |> validate_inclusion(:status, @statuses)
    |> assoc_constraint(:project)
    |> unique_constraint(:project_id)
  end

  def sandbox_modes, do: @sandbox_modes
  def statuses, do: @statuses
end
