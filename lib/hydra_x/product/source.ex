defmodule HydraX.Product.Source do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(pending processing completed failed)

  schema "sources" do
    field :title, :string
    field :source_type, :string
    field :content, :string
    field :external_ref, :string
    field :processing_status, :string, default: "pending"
    field :reviewed_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    # Source-as-Data (Cycle 3): sources default to Library-only. Only
    # explicitly promoted sources appear in the graph. `archived_at` lets
    # users de-emphasise sources without deleting them.
    field :promoted_to_graph, :boolean, default: false
    field :promoted_at, :utc_datetime_usec
    field :archived_at, :utc_datetime_usec

    belongs_to :project, HydraX.Product.Project
    has_many :source_chunks, HydraX.Product.SourceChunk
    has_many :source_references, HydraX.Product.SourceReference

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(source, attrs) do
    source
    |> cast(attrs, [
      :project_id,
      :title,
      :source_type,
      :content,
      :external_ref,
      :processing_status,
      :reviewed_at,
      :metadata,
      :promoted_to_graph,
      :promoted_at,
      :archived_at
    ])
    |> validate_required([:project_id, :title, :source_type, :processing_status])
    |> validate_inclusion(:processing_status, @statuses)
    |> foreign_key_constraint(:project_id)
  end
end
