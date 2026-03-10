defmodule HydraX.Runtime.SkillInstall do
  use Ecto.Schema
  import Ecto.Changeset

  schema "skill_installs" do
    field :slug, :string
    field :name, :string
    field :path, :string
    field :description, :string
    field :source, :string, default: "workspace"
    field :enabled, :boolean, default: true
    field :metadata, :map, default: %{}

    belongs_to :agent, HydraX.Runtime.AgentProfile

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(skill, attrs) do
    skill
    |> cast(attrs, [:agent_id, :slug, :name, :path, :description, :source, :enabled, :metadata])
    |> validate_required([:agent_id, :slug, :name, :path, :source])
    |> unique_constraint([:agent_id, :slug], name: :skill_installs_agent_id_slug_index)
  end
end
