defmodule HydraX.Product.Vision do
  @moduledoc """
  Root node of a project's graph — the "why the project exists".

  One Vision per project (enforced by unique index). Everything else in
  the graph hangs off this; the Why-button walks lineage up to it.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias HydraX.Product.Scope

  @statuses ~w(active archived superseded)

  schema "visions" do
    field :title, :string
    field :body, :string
    field :status, :string, default: "active"
    field :metadata, :map, default: %{}

    field :scope, :string, default: "project"
    field :scope_root_id, :integer

    belongs_to :project, HydraX.Product.Project

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(vision, attrs) do
    vision
    |> cast(attrs, [:project_id, :title, :body, :status, :metadata, :scope, :scope_root_id])
    |> validate_required([:project_id, :title, :status])
    |> validate_inclusion(:status, @statuses)
    |> Scope.validate_and_default()
    |> unique_constraint(:project_id)
    |> foreign_key_constraint(:project_id)
  end
end
