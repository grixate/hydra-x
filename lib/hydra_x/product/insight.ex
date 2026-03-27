defmodule HydraX.Product.Insight do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(draft accepted rejected)

  schema "insights" do
    field :title, :string
    field :body, :string
    field :status, :string, default: "draft"
    field :metadata, :map, default: %{}

    belongs_to :project, HydraX.Product.Project
    has_many :insight_evidence, HydraX.Product.InsightEvidence
    has_many :requirement_insights, HydraX.Product.RequirementInsight

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(insight, attrs) do
    insight
    |> cast(attrs, [:project_id, :title, :body, :status, :metadata])
    |> validate_required([:project_id, :title, :body, :status])
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:project_id)
  end
end
