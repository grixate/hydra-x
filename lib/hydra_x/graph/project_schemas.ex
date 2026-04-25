defmodule HydraX.Graph.ProjectSchemas do
  @moduledoc """
  CRUD for a project's schema definitions (node, relationship, and flag
  type definitions). Per the Part 1 amendment, schemas are project-scoped:
  every project owns its own complete set of definitions, populated either
  by applying a pretrained project at creation time or by approving
  schema-change proposals at runtime.

  Writes here update the `SchemaRegistry` ETS cache directly so readers
  don't have to round-trip through the DB.
  """

  import Ecto.Query, warn: false

  alias HydraX.Graph.FlagTypeDefinition
  alias HydraX.Graph.NodeTypeDefinition
  alias HydraX.Graph.RelationshipTypeDefinition
  alias HydraX.Graph.SchemaRegistry
  alias HydraX.Repo

  # Node type definitions

  def list_node_types(project_id) when is_integer(project_id) do
    Repo.all(
      from n in NodeTypeDefinition,
        where: n.project_id == ^project_id,
        order_by: n.type_key
    )
  end

  def upsert_node_type(project_id, attrs) when is_integer(project_id) do
    type_key = Map.get(attrs, :type_key) || Map.get(attrs, "type_key")

    existing =
      Repo.get_by(NodeTypeDefinition, project_id: project_id, type_key: type_key)

    result =
      (existing || %NodeTypeDefinition{})
      |> NodeTypeDefinition.changeset(Map.put(attrs, :project_id, project_id))
      |> Repo.insert_or_update()

    with {:ok, def} <- result, do: SchemaRegistry.put_node_type(project_id, def)
    result
  end

  # Relationship type definitions

  def list_relationship_types(project_id) when is_integer(project_id) do
    Repo.all(
      from r in RelationshipTypeDefinition,
        where: r.project_id == ^project_id,
        order_by: r.type_key
    )
  end

  def upsert_relationship_type(project_id, attrs) when is_integer(project_id) do
    type_key = Map.get(attrs, :type_key) || Map.get(attrs, "type_key")

    existing =
      Repo.get_by(RelationshipTypeDefinition, project_id: project_id, type_key: type_key)

    result =
      (existing || %RelationshipTypeDefinition{})
      |> RelationshipTypeDefinition.changeset(Map.put(attrs, :project_id, project_id))
      |> Repo.insert_or_update()

    with {:ok, def} <- result, do: SchemaRegistry.put_relationship_type(project_id, def)
    result
  end

  # Flag type definitions

  def list_flag_types(project_id) when is_integer(project_id) do
    Repo.all(
      from f in FlagTypeDefinition,
        where: f.project_id == ^project_id,
        order_by: f.type_key
    )
  end

  def upsert_flag_type(project_id, attrs) when is_integer(project_id) do
    type_key = Map.get(attrs, :type_key) || Map.get(attrs, "type_key")

    existing =
      Repo.get_by(FlagTypeDefinition, project_id: project_id, type_key: type_key)

    result =
      (existing || %FlagTypeDefinition{})
      |> FlagTypeDefinition.changeset(Map.put(attrs, :project_id, project_id))
      |> Repo.insert_or_update()

    with {:ok, def} <- result, do: SchemaRegistry.put_flag_type(project_id, def)
    result
  end
end
