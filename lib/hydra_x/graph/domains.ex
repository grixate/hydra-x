defmodule HydraX.Graph.Domains do
  @moduledoc """
  CRUD for domains and their schema definitions. Writes here invalidate
  the `SchemaRegistry` cache for the affected domain so the next read
  picks up fresh data.
  """

  import Ecto.Query, warn: false

  alias HydraX.Graph.Domain
  alias HydraX.Graph.FlagTypeDefinition
  alias HydraX.Graph.NodeTypeDefinition
  alias HydraX.Graph.RelationshipTypeDefinition
  alias HydraX.Graph.SchemaRegistry
  alias HydraX.Repo

  # Domains

  def list_domains do
    Repo.all(Domain)
  end

  def get_domain!(id), do: Repo.get!(Domain, id)

  def get_domain_by_slug(slug) when is_binary(slug) do
    Repo.get_by(Domain, slug: slug)
  end

  def upsert_domain(attrs) do
    slug = Map.get(attrs, :slug) || Map.get(attrs, "slug")

    case get_domain_by_slug(slug) do
      nil -> create_domain(attrs)
      %Domain{} = existing -> update_domain(existing, attrs)
    end
  end

  def create_domain(attrs) do
    %Domain{}
    |> Domain.changeset(attrs)
    |> Repo.insert()
  end

  def update_domain(%Domain{} = domain, attrs) do
    result =
      domain
      |> Domain.changeset(attrs)
      |> Repo.update()

    case result do
      {:ok, updated} ->
        SchemaRegistry.invalidate(updated.id)
        {:ok, updated}

      other ->
        other
    end
  end

  # Node type definitions

  def list_node_types(%Domain{id: id}), do: list_node_types(id)

  def list_node_types(domain_id) when is_integer(domain_id) do
    Repo.all(from n in NodeTypeDefinition, where: n.domain_id == ^domain_id, order_by: n.type_key)
  end

  def upsert_node_type(%Domain{} = domain, attrs) do
    type_key = Map.get(attrs, :type_key) || Map.get(attrs, "type_key")

    existing =
      Repo.get_by(NodeTypeDefinition, domain_id: domain.id, type_key: type_key)

    result =
      (existing || %NodeTypeDefinition{})
      |> NodeTypeDefinition.changeset(Map.put(attrs, :domain_id, domain.id))
      |> Repo.insert_or_update()

    with {:ok, def} <- result, do: SchemaRegistry.put_node_type(domain.id, def)
    result
  end

  # Relationship type definitions

  def upsert_relationship_type(%Domain{} = domain, attrs) do
    type_key = Map.get(attrs, :type_key) || Map.get(attrs, "type_key")

    existing =
      Repo.get_by(RelationshipTypeDefinition, domain_id: domain.id, type_key: type_key)

    result =
      (existing || %RelationshipTypeDefinition{})
      |> RelationshipTypeDefinition.changeset(Map.put(attrs, :domain_id, domain.id))
      |> Repo.insert_or_update()

    with {:ok, def} <- result, do: SchemaRegistry.put_relationship_type(domain.id, def)
    result
  end

  # Flag type definitions

  def upsert_flag_type(%Domain{} = domain, attrs) do
    type_key = Map.get(attrs, :type_key) || Map.get(attrs, "type_key")

    existing =
      Repo.get_by(FlagTypeDefinition, domain_id: domain.id, type_key: type_key)

    result =
      (existing || %FlagTypeDefinition{})
      |> FlagTypeDefinition.changeset(Map.put(attrs, :domain_id, domain.id))
      |> Repo.insert_or_update()

    with {:ok, def} <- result, do: SchemaRegistry.put_flag_type(domain.id, def)
    result
  end
end
