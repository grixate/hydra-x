defmodule HydraX.Product.KnowledgeEntry do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(active pending_review archived)
  @entry_types ~w(design_language coding_conventions brand_guide product_vision domain_knowledge process_rules integration_docs custom)
  @source_types ~w(manual url generated)

  schema "knowledge_entries" do
    field :title, :string
    field :content, :string
    field :entry_type, :string, default: "custom"
    field :assigned_personas, {:array, :string}, default: []
    field :source_type, :string, default: "manual"
    field :source_url, :string
    field :status, :string, default: "active"
    field :embedding, Pgvector.Ecto.Vector
    field :metadata, :map, default: %{}

    belongs_to :project, HydraX.Product.Project

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [
      :project_id, :title, :content, :entry_type, :assigned_personas,
      :source_type, :source_url, :status, :embedding, :metadata
    ])
    |> validate_required([:project_id, :title, :content, :entry_type, :status])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:entry_type, @entry_types)
    |> validate_inclusion(:source_type, @source_types)
    |> foreign_key_constraint(:project_id)
  end
end
