defmodule HydraX.Runtime.Artifact do
  use Ecto.Schema
  import Ecto.Changeset

  @review_statuses ~w(draft proposed validated approved rejected superseded)

  schema "hx_artifacts" do
    field :type, :string
    field :title, :string
    field :summary, :string
    field :body, :string
    field :payload, :map, default: %{}
    field :version, :integer, default: 1
    field :provenance, :map, default: %{}
    field :confidence, :float
    field :review_status, :string, default: "draft"
    field :metadata, :map, default: %{}

    belongs_to :work_item, HydraX.Runtime.WorkItem

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(artifact, attrs) do
    artifact
    |> cast(attrs, [
      :type,
      :title,
      :summary,
      :body,
      :payload,
      :version,
      :provenance,
      :confidence,
      :review_status,
      :metadata,
      :work_item_id
    ])
    |> validate_required([:type, :title, :work_item_id])
    |> validate_number(:version, greater_than_or_equal_to: 1)
    |> validate_inclusion(:review_status, @review_statuses)
    |> validate_number(:confidence, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> assoc_constraint(:work_item)
  end
end
