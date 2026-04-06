defmodule HydraX.Product.ArtifactVersion do
  use Ecto.Schema
  import Ecto.Changeset

  schema "artifact_versions" do
    field :version, :integer
    field :body, :string
    field :change_summary, :string
    field :updated_by, :string
    field :metadata, :map, default: %{}

    belongs_to :artifact, HydraX.Product.Artifact

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(version, attrs) do
    version
    |> cast(attrs, [:artifact_id, :version, :body, :change_summary, :updated_by, :metadata])
    |> validate_required([:artifact_id, :version, :body, :updated_by])
    |> unique_constraint([:artifact_id, :version])
    |> foreign_key_constraint(:artifact_id)
  end
end
