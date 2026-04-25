defmodule HydraX.Graph.SchemaRegistry do
  @moduledoc """
  In-memory cache of project schema definitions. Reads happen against
  ETS with no GenServer bottleneck; writes (cache invalidation) go
  through the owner process and are broadcast via PubSub so every node
  in the cluster refreshes its cache on the next read.

  Per the Part 1 amendment, schemas are project-scoped — every project
  owns its own complete schema, so the cache is keyed by `project_id`.

  Consulted on every node write to validate `attributes` against the
  declaring type's `attribute_schema`. Performance matters — keeping
  this out of the hot path for lookups is the point of the ETS design.
  """

  use GenServer
  import Ecto.Query, warn: false
  require Logger

  alias HydraX.Graph.FlagTypeDefinition
  alias HydraX.Graph.NodeTypeDefinition
  alias HydraX.Graph.Primitives
  alias HydraX.Graph.RelationshipTypeDefinition
  alias HydraX.Repo

  @table :hydra_x_graph_schema_registry
  @pubsub_topic "graph:schema"

  # Public API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Fetch a node type definition. Returns `{:ok, def}` when found, `:error`
  otherwise. Lazy-loads the project's schema on first access.
  """
  def fetch_node_type(project_id, type_key) do
    fetch(:node_type, project_id, type_key)
  end

  def fetch_relationship_type(project_id, type_key) do
    fetch(:relationship_type, project_id, type_key)
  end

  def fetch_flag_type(project_id, type_key) do
    fetch(:flag_type, project_id, type_key)
  end

  def list_node_types(project_id) do
    ensure_loaded(project_id)

    :ets.match_object(@table, {{:node_type, project_id, :_}, :_})
    |> Enum.map(fn {_key, value} -> value end)
  end

  @doc """
  Validate a node's `attributes` map against the declaring type's
  `attribute_schema`. Returns `:ok` or `{:error, [field: message]}`.

  Supports the subset of JSON Schema we actually need: `type`, `required`,
  `enum`, and rejection of unknown fields when `additionalProperties` is
  false. Extend as needed.
  """
  def validate_attributes(attribute_schema, attributes)
      when is_map(attribute_schema) and is_map(attributes) do
    properties = Map.get(attribute_schema, "properties", %{})
    required = Map.get(attribute_schema, "required", [])
    additional_properties = Map.get(attribute_schema, "additionalProperties", true)
    stringified = stringify_keys(attributes)

    errors =
      []
      |> check_required(required, stringified)
      |> check_property_types(properties, stringified)
      |> check_additional_properties(properties, stringified, additional_properties)

    case errors do
      [] -> :ok
      _ -> {:error, Enum.reverse(errors)}
    end
  end

  def validate_attributes(_, _), do: :ok

  @doc """
  Invalidate the cache for a project. Safe to call from any process;
  broadcasts to all cluster nodes so every local registry drops its
  entries for this project.
  """
  def invalidate(project_id) do
    Phoenix.PubSub.broadcast(HydraX.PubSub, @pubsub_topic, {:schema_invalidated, project_id})
  end

  @doc """
  Put a definition directly into the cache. Used by `Graph.ProjectSchemas`
  on upsert so readers don't have to round-trip through the DB to refresh.
  Safe to call from the calling process — writes to a public ETS table.
  """
  def put_node_type(project_id, %NodeTypeDefinition{} = def) do
    :ets.insert(@table, {{:node_type, project_id, def.type_key}, def})
    :ok
  end

  def put_relationship_type(project_id, %RelationshipTypeDefinition{} = def) do
    :ets.insert(@table, {{:relationship_type, project_id, def.type_key}, def})
    :ok
  end

  def put_flag_type(project_id, %FlagTypeDefinition{} = def) do
    :ets.insert(@table, {{:flag_type, project_id, def.type_key}, def})
    :ok
  end

  # GenServer

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    Phoenix.PubSub.subscribe(HydraX.PubSub, @pubsub_topic)
    {:ok, %{}}
  end

  @impl true
  def handle_info({:schema_invalidated, project_id}, state) do
    drop_project(project_id)
    {:noreply, state}
  end

  def handle_info({:schema_updated, project_id}, state) do
    drop_project(project_id)
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # Internals

  defp fetch(kind, project_id, type_key) do
    case :ets.lookup(@table, {kind, project_id, type_key}) do
      [{_key, value}] ->
        {:ok, value}

      [] ->
        # Cache miss — ensure the project is loaded, then retry.
        ensure_loaded(project_id)

        case :ets.lookup(@table, {kind, project_id, type_key}) do
          [{_key, value}] -> {:ok, value}
          [] -> :error
        end
    end
  end

  # Runs DB queries in the caller's process so they participate in any
  # active Ecto sandbox connection. Idempotent — multiple processes
  # racing to load the same project just write the same rows to ETS.
  defp ensure_loaded(project_id) do
    case :ets.lookup(@table, {:loaded, project_id}) do
      [{_, _}] ->
        :ok

      [] ->
        load_project(project_id)
        :ets.insert(@table, {{:loaded, project_id}, true})
        :ok
    end
  end

  defp load_project(project_id) do
    node_types = Repo.all(from n in NodeTypeDefinition, where: n.project_id == ^project_id)
    rel_types = Repo.all(from r in RelationshipTypeDefinition, where: r.project_id == ^project_id)
    flag_types = Repo.all(from f in FlagTypeDefinition, where: f.project_id == ^project_id)

    Enum.each(node_types, fn t ->
      :ets.insert(@table, {{:node_type, project_id, t.type_key}, t})
    end)

    Enum.each(rel_types, fn t ->
      :ets.insert(@table, {{:relationship_type, project_id, t.type_key}, t})
    end)

    Enum.each(flag_types, fn t ->
      :ets.insert(@table, {{:flag_type, project_id, t.type_key}, t})
    end)

    Logger.debug(fn ->
      "[SchemaRegistry] loaded project #{project_id}: " <>
        "#{length(node_types)} nodes, #{length(rel_types)} rels, #{length(flag_types)} flags"
    end)
  end

  defp drop_project(project_id) do
    :ets.match_delete(@table, {{:node_type, project_id, :_}, :_})
    :ets.match_delete(@table, {{:relationship_type, project_id, :_}, :_})
    :ets.match_delete(@table, {{:flag_type, project_id, :_}, :_})
    :ets.delete(@table, {:loaded, project_id})
  end

  # Attribute validation helpers

  defp check_required(errors, required, attributes) do
    Enum.reduce(required, errors, fn field, acc ->
      if Map.has_key?(attributes, field),
        do: acc,
        else: [{field, "is required"} | acc]
    end)
  end

  defp check_property_types(errors, properties, attributes) do
    Enum.reduce(properties, errors, fn {field, spec}, acc ->
      case Map.fetch(attributes, field) do
        {:ok, value} -> validate_value(acc, field, spec, value)
        :error -> acc
      end
    end)
  end

  defp check_additional_properties(errors, _properties, _attributes, true), do: errors

  defp check_additional_properties(errors, properties, attributes, false) do
    allowed = Map.keys(properties) |> MapSet.new()

    attributes
    |> Map.keys()
    |> Enum.reduce(errors, fn key, acc ->
      if MapSet.member?(allowed, key), do: acc, else: [{key, "is not a declared attribute"} | acc]
    end)
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end

  defp validate_value(errors, field, spec, value) do
    errors
    |> validate_type(field, spec, value)
    |> validate_enum(field, spec, value)
  end

  defp validate_type(errors, field, %{"type" => expected}, value) do
    if matches_type?(expected, value) do
      errors
    else
      [{field, "expected type #{expected}"} | errors]
    end
  end

  defp validate_type(errors, _field, _spec, _value), do: errors

  defp validate_enum(errors, field, %{"enum" => allowed}, value) do
    if value in allowed, do: errors, else: [{field, "is not in allowed values"} | errors]
  end

  defp validate_enum(errors, _field, _spec, _value), do: errors

  defp matches_type?("string", value), do: is_binary(value)
  defp matches_type?("integer", value), do: is_integer(value)
  defp matches_type?("number", value), do: is_number(value)
  defp matches_type?("boolean", value), do: is_boolean(value)
  defp matches_type?("array", value), do: is_list(value)
  defp matches_type?("object", value), do: is_map(value)
  defp matches_type?("null", value), do: is_nil(value)
  defp matches_type?(_, _), do: true

  @doc false
  def __primitives__, do: Primitives
end
