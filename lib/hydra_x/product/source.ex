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
    field :metadata, :map, default: %{}

    belongs_to :project, HydraX.Product.Project
    has_many :source_chunks, HydraX.Product.SourceChunk

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
      :metadata
    ])
    |> validate_required([:project_id, :title, :source_type, :processing_status])
    |> validate_inclusion(:processing_status, @statuses)
    |> foreign_key_constraint(:project_id)
  end
end
