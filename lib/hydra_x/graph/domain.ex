defmodule HydraX.Graph.Domain do
  @moduledoc """
  A domain is the container for schema definitions and is the unit of
  configuration loading. Every project references exactly one domain.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(active draft deprecated)
  @sources ~w(builtin user_defined)

  schema "domains" do
    field :slug, :string
    field :name, :string
    field :version, :string, default: "0.1.0"
    field :status, :string, default: "active"
    field :source, :string, default: "builtin"
    field :metadata, :map, default: %{}

    has_many :node_type_definitions, HydraX.Graph.NodeTypeDefinition
    has_many :relationship_type_definitions, HydraX.Graph.RelationshipTypeDefinition
    has_many :flag_type_definitions, HydraX.Graph.FlagTypeDefinition

    timestamps(type: :utc_datetime_usec)
  end

  def statuses, do: @statuses
  def sources, do: @sources

  def changeset(domain, attrs) do
    domain
    |> cast(attrs, [:slug, :name, :version, :status, :source, :metadata])
    |> validate_required([:slug, :name, :version, :status, :source])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:source, @sources)
    |> validate_format(:slug, ~r/^[a-z][a-z0-9_]*$/,
      message: "must be lowercase snake_case starting with a letter"
    )
    |> unique_constraint(:slug)
  end
end
