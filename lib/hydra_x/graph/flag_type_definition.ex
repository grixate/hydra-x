defmodule HydraX.Graph.FlagTypeDefinition do
  @moduledoc """
  Declares a flag type within a project (e.g. `orphan`, `contradicted`,
  `stale`). Severity defaults come from the definition; individual flag
  rows may override. Per the Part 1 amendment, scoped to project.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @severities ~w(info warning critical)

  schema "flag_type_definitions" do
    field :type_key, :string
    field :display_name, :string
    field :description, :string
    field :default_severity, :string, default: "warning"

    belongs_to :project, HydraX.Product.Project

    timestamps(type: :utc_datetime_usec)
  end

  def severities, do: @severities

  def changeset(definition, attrs) do
    definition
    |> cast(attrs, [:project_id, :type_key, :display_name, :description, :default_severity])
    |> validate_required([:project_id, :type_key, :display_name, :default_severity])
    |> validate_format(:type_key, ~r/^[a-z][a-z0-9_]*$/,
      message: "must be lowercase snake_case starting with a letter"
    )
    |> validate_inclusion(:default_severity, @severities)
    |> unique_constraint([:project_id, :type_key])
    |> foreign_key_constraint(:project_id)
  end
end
