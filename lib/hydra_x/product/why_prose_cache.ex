defmodule HydraX.Product.WhyProseCache do
  @moduledoc """
  Server-side cache of Why-button prose explanations. Keyed by
  `(project_id, node_type, node_id, cache_key)` where `cache_key` is a
  stable hash of the lineage-chain content (spec §6).
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "why_prose_cache" do
    field :node_type, :string
    field :node_id, :integer
    field :cache_key, :string
    field :prose, :string
    field :model_id, :string
    field :generated_at, :utc_datetime_usec

    belongs_to :project, HydraX.Product.Project

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:project_id, :node_type, :node_id, :cache_key, :prose, :model_id, :generated_at])
    |> validate_required([:project_id, :node_type, :node_id, :cache_key, :prose, :generated_at])
    |> unique_constraint([:project_id, :node_type, :node_id, :cache_key])
    |> foreign_key_constraint(:project_id)
  end
end
