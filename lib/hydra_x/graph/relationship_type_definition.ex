defmodule HydraX.Graph.RelationshipTypeDefinition do
  @moduledoc """
  Declares a relationship type within a project: the allowed endpoint
  types, cardinality, directionality, and optional attribute shape.
  Per the Part 1 amendment, scoped to project, not domain.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias HydraX.Graph.Primitives

  @cardinalities ~w(one_to_one one_to_many many_to_many)

  schema "relationship_type_definitions" do
    field :type_key, :string
    field :display_name, :string
    field :description, :string
    field :extends, :string
    field :valid_from_types, {:array, :string}, default: ["*"]
    field :valid_to_types, {:array, :string}, default: ["*"]
    field :cardinality, :string, default: "many_to_many"
    field :directional, :boolean, default: true
    field :attribute_schema, :map, default: %{}

    belongs_to :project, HydraX.Product.Project

    timestamps(type: :utc_datetime_usec)
  end

  def cardinalities, do: @cardinalities

  def changeset(definition, attrs) do
    definition
    |> cast(attrs, [
      :project_id,
      :type_key,
      :display_name,
      :description,
      :extends,
      :valid_from_types,
      :valid_to_types,
      :cardinality,
      :directional,
      :attribute_schema
    ])
    |> validate_required([:project_id, :type_key, :display_name, :cardinality])
    |> validate_format(:type_key, ~r/^[a-z][a-z0-9_]*$/,
      message: "must be lowercase snake_case starting with a letter"
    )
    |> validate_inclusion(:cardinality, @cardinalities)
    |> validate_change(:extends, fn :extends, value ->
      cond do
        is_nil(value) -> []
        Primitives.relationship_primitive?(value) -> []
        true -> [extends: "is not a known base relationship primitive"]
      end
    end)
    |> unique_constraint([:project_id, :type_key])
    |> foreign_key_constraint(:project_id)
  end
end
