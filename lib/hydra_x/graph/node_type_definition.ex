defmodule HydraX.Graph.NodeTypeDefinition do
  @moduledoc """
  Declares a node type within a domain: its attribute shape, status
  vocabulary, promotion sources, and the base primitive it extends.

  Replaces hardcoded Ecto modules like `HydraX.Product.Insight`,
  `HydraX.Product.Decision`, etc. Adding a new type becomes an
  `INSERT` rather than a deployment.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias HydraX.Graph.Domain
  alias HydraX.Graph.Primitives

  schema "node_type_definitions" do
    field :type_key, :string
    field :display_name, :string
    field :description, :string
    field :extends, :string
    field :attribute_schema, :map, default: %{}
    field :status_vocabulary, {:array, :string}, default: []
    field :promotion_sources, {:array, :string}, default: []
    field :icon, :string
    field :color_token, :string
    field :version, :integer, default: 1

    belongs_to :domain, Domain

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(definition, attrs) do
    definition
    |> cast(attrs, [
      :domain_id,
      :type_key,
      :display_name,
      :description,
      :extends,
      :attribute_schema,
      :status_vocabulary,
      :promotion_sources,
      :icon,
      :color_token,
      :version
    ])
    |> validate_required([:domain_id, :type_key, :display_name, :version])
    |> validate_format(:type_key, ~r/^[a-z][a-z0-9_]*$/,
      message: "must be lowercase snake_case starting with a letter"
    )
    |> validate_change(:extends, fn :extends, value ->
      cond do
        is_nil(value) -> []
        Primitives.node_primitive?(value) -> []
        true -> [extends: "is not a known base primitive"]
      end
    end)
    |> unique_constraint([:domain_id, :type_key])
    |> foreign_key_constraint(:domain_id)
  end
end
