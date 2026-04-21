defmodule HydraX.Product.Artifact do
  use Ecto.Schema
  import Ecto.Changeset

  @artifact_types ~w(competitive_analysis strategy_memo project_summary decision_log design_language spec campaign report reference brief custom)
  @statuses ~w(active archived)

  schema "artifacts" do
    field :title, :string
    field :artifact_type, :string
    field :body, :string
    field :owner_persona, :string
    field :status, :string, default: "active"
    field :version, :integer, default: 1
    field :last_updated_by, :string
    field :metadata, :map, default: %{}

    belongs_to :project, HydraX.Product.Project
    has_many :versions, HydraX.Product.ArtifactVersion

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(artifact, attrs) do
    artifact
    |> cast(attrs, [
      :project_id, :title, :artifact_type, :body, :owner_persona,
      :status, :version, :last_updated_by, :metadata
    ])
    |> validate_required([:project_id, :title, :artifact_type, :body, :owner_persona])
    |> validate_inclusion(:artifact_type, @artifact_types)
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:project_id)
  end

  @doc """
  Changeset for updates that enforces optimistic locking via the version field.
  Ecto's optimistic_lock adds WHERE version = current AND increments it atomically.
  """
  def update_changeset(artifact, attrs) do
    artifact
    |> cast(attrs, [:title, :body, :status, :last_updated_by, :metadata])
    |> validate_required([:body, :last_updated_by])
    |> optimistic_lock(:version)
  end

  def artifact_types, do: @artifact_types
end
