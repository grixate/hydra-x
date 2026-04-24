defmodule HydraX.Graph.Node do
  @moduledoc """
  The single table that replaces `insights`, `decisions`, `requirements`,
  `strategies`, `constraints`, `design_nodes`, `architecture_nodes`, and
  any future domain-specific entity types. Type-specific fields live in
  `attributes` and are validated against the `NodeTypeDefinition`'s
  `attribute_schema` on write via `SchemaRegistry`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias HydraX.Graph.Domain
  alias HydraX.Graph.Primitives
  alias HydraX.Graph.SchemaRegistry

  schema "nodes" do
    field :type_key, :string
    field :extends_primitive, :string
    field :title, :string
    field :body, :string
    field :attributes, :map, default: %{}
    field :status, :string
    field :importance, :float
    field :confidence, :float
    field :scope, :string, default: "project"
    field :scope_root_id, :integer
    field :lock_version, :integer, default: 1
    field :created_by_agent_id, :string
    field :created_by_operator, :boolean, default: false
    field :archived_at, :utc_datetime_usec

    belongs_to :domain, Domain
    belongs_to :project, HydraX.Product.Project

    # Transitional: while the product domain's join tables (`insight_evidence`,
    # `requirement_insights`) still live in `lib/hydra_x/product/`, they
    # reference `nodes.id` as an integer FK. These associations let the
    # Product context preload evidence/requirements without bypassing Ecto.
    # Remove once those join tables become generic `node_relationships`.
    has_many :insight_evidence, HydraX.Product.InsightEvidence, foreign_key: :insight_id

    # Note: `requirement_insights` appears under two fks, so we expose it
    # under two names. `as_insight` — rows where this node is the insight
    # side; `as_requirement` — where this node is the requirement side.
    has_many :requirement_insights,
             HydraX.Product.RequirementInsight,
             foreign_key: :insight_id

    has_many :linked_requirement_insights,
             HydraX.Product.RequirementInsight,
             foreign_key: :requirement_id

    has_many :artifact_versions,
             HydraX.Product.ArtifactVersion,
             foreign_key: :artifact_id

    has_many :routine_runs,
             HydraX.Product.RoutineRun,
             foreign_key: :routine_id

    has_many :task_feedback,
             HydraX.Product.TaskFeedback,
             foreign_key: :task_id

    has_many :source_chunks,
             HydraX.Product.SourceChunk,
             foreign_key: :source_id

    has_many :source_references,
             HydraX.Product.SourceReference,
             foreign_key: :source_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(node, attrs) do
    node
    |> cast(attrs, [
      :domain_id,
      :project_id,
      :type_key,
      :extends_primitive,
      :title,
      :body,
      :attributes,
      :status,
      :importance,
      :confidence,
      :scope,
      :scope_root_id,
      :lock_version,
      :created_by_agent_id,
      :created_by_operator,
      :archived_at
    ])
    |> validate_required([
      :domain_id,
      :project_id,
      :type_key,
      :title,
      :status,
      :scope
    ])
    |> validate_change(:extends_primitive, fn :extends_primitive, value ->
      cond do
        is_nil(value) -> []
        Primitives.node_primitive?(value) -> []
        true -> [extends_primitive: "is not a known base primitive"]
      end
    end)
    |> validate_against_registry()
    |> foreign_key_constraint(:domain_id)
    |> foreign_key_constraint(:project_id)
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
    case SchemaRegistry.fetch_node_type(domain_id, type_key) do
      :error ->
        add_error(changeset, :type_key, "is not defined for this domain")

      {:ok, type_def} ->
        changeset
        |> maybe_denormalize_primitive(type_def)
        |> validate_status_against_vocabulary(type_def)
        |> validate_attributes_against_schema(type_def)
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

  defp validate_status_against_vocabulary(changeset, type_def) do
    vocabulary = type_def.status_vocabulary || []
    status = get_field(changeset, :status)

    cond do
      vocabulary == [] -> changeset
      status in vocabulary -> changeset
      true -> add_error(changeset, :status, "is not in the type's status vocabulary")
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

  @doc """
  Changeset for state-machine transitions. Applies optimistic locking so
  concurrent writes on the same node cannot silently clobber each other.
  """
  def transition_changeset(node, attrs) do
    node
    |> changeset(attrs)
    |> optimistic_lock(:lock_version)
  end
end
