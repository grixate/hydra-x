defmodule HydraX.Graph.NodeRelationship do
  @moduledoc """
  Replaces `product_graph_edges`, generalised. An edge between two `Node`s
  whose `type_key` must exist in the domain's
  `RelationshipTypeDefinition`. Endpoint compatibility (which type can
  point at which) is enforced by `SchemaRegistry` at write time.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias HydraX.Graph.Domain
  alias HydraX.Graph.Node
  alias HydraX.Graph.Primitives
  alias HydraX.Graph.SchemaRegistry
  alias HydraX.Repo

  schema "node_relationships" do
    field :type_key, :string
    field :extends_primitive, :string
    field :weight, :float, default: 1.0
    field :attributes, :map, default: %{}
    field :created_by_agent_id, :string

    # Denormalized from the referenced nodes' type_keys. Populated at
    # write time so readers that filter by endpoint type (graph
    # traversal, ProductPayload, etc.) don't need a join.
    field :from_node_type, :string
    field :to_node_type, :string

    belongs_to :domain, Domain
    belongs_to :project, HydraX.Product.Project
    belongs_to :from_node, Node
    belongs_to :to_node, Node

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(relationship, attrs) do
    relationship
    |> cast(attrs, [
      :domain_id,
      :project_id,
      :type_key,
      :extends_primitive,
      :from_node_id,
      :to_node_id,
      :from_node_type,
      :to_node_type,
      :weight,
      :attributes,
      :created_by_agent_id
    ])
    |> validate_required([:domain_id, :project_id, :type_key, :from_node_id, :to_node_id])
    |> validate_change(:extends_primitive, fn :extends_primitive, value ->
      cond do
        is_nil(value) -> []
        Primitives.relationship_primitive?(value) -> []
        true -> [extends_primitive: "is not a known base relationship primitive"]
      end
    end)
    |> validate_against_registry()
    |> foreign_key_constraint(:domain_id)
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:from_node_id)
    |> foreign_key_constraint(:to_node_id)
    |> unique_constraint([:from_node_id, :to_node_id, :type_key],
      name: :node_relationships_from_node_id_to_node_id_type_key_index
    )
  end

  defp validate_against_registry(changeset) do
    domain_id = get_field(changeset, :domain_id)
    type_key = get_field(changeset, :type_key)

    cond do
      !changeset.valid? -> changeset
      is_nil(domain_id) or is_nil(type_key) -> changeset
      true -> apply_type_definition(changeset, domain_id, type_key)
    end
  end

  defp apply_type_definition(changeset, domain_id, type_key) do
    case SchemaRegistry.fetch_relationship_type(domain_id, type_key) do
      :error ->
        add_error(changeset, :type_key, "is not defined for this domain")

      {:ok, type_def} ->
        changeset
        |> maybe_denormalize_primitive(type_def)
        |> denormalize_endpoint_types()
        |> validate_endpoint_types(type_def)
        |> validate_attributes_against_schema(type_def)
    end
  end

  defp denormalize_endpoint_types(changeset) do
    changeset
    |> denormalize_endpoint_type(:from_node_id, :from_node_type)
    |> denormalize_endpoint_type(:to_node_id, :to_node_type)
  end

  defp denormalize_endpoint_type(changeset, id_field, type_field) do
    if is_nil(get_field(changeset, type_field)) do
      node_id = get_field(changeset, id_field)

      case node_id && Repo.get(Node, node_id) do
        %Node{type_key: type_key} -> put_change(changeset, type_field, type_key)
        _ -> changeset
      end
    else
      changeset
    end
  end

  defp validate_endpoint_types(changeset, type_def) do
    valid_from = type_def.valid_from_types || ["*"]
    valid_to = type_def.valid_to_types || ["*"]

    with true <- wildcard?(valid_from) or endpoint_ok?(changeset, :from_node_id, valid_from),
         true <- wildcard?(valid_to) or endpoint_ok?(changeset, :to_node_id, valid_to) do
      changeset
    else
      {:error, side} ->
        add_error(changeset, side, "endpoint type is not permitted for this relationship type")
    end
  end

  defp wildcard?(types), do: "*" in types

  defp endpoint_ok?(changeset, field, allowed) do
    node_id = get_field(changeset, field)

    case node_id && Repo.get(Node, node_id) do
      %Node{type_key: type_key} ->
        if type_key in allowed, do: true, else: {:error, field}

      _ ->
        # Missing endpoint gets caught by foreign_key_constraint.
        true
    end
  end

  defp maybe_denormalize_primitive(changeset, type_def) do
    case {get_field(changeset, :extends_primitive), type_def.extends} do
      {nil, nil} ->
        changeset

      {nil, primitive} ->
        put_change(changeset, :extends_primitive, primitive)

      {value, primitive} when value == primitive ->
        changeset

      {_value, nil} ->
        changeset

      {_value, _primitive} ->
        add_error(changeset, :extends_primitive, "does not match type definition")
    end
  end

  defp validate_attributes_against_schema(changeset, type_def) do
    attributes = get_field(changeset, :attributes) || %{}
    schema = type_def.attribute_schema || %{}

    case SchemaRegistry.validate_attributes(schema, attributes) do
      :ok ->
        changeset

      {:error, errors} ->
        Enum.reduce(errors, changeset, fn {field, message}, acc ->
          add_error(acc, :attributes, "#{field} #{message}")
        end)
    end
  end
end
