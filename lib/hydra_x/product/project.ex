defmodule HydraX.Product.Project do
  use Ecto.Schema
  import Ecto.Changeset

  alias HydraX.Runtime.AgentProfile

  @statuses ~w(active archived)

  schema "projects" do
    field :name, :string
    field :slug, :string
    field :description, :string
    field :status, :string, default: "active"
    field :metadata, :map, default: %{}

    belongs_to :researcher_agent, AgentProfile
    belongs_to :strategist_agent, AgentProfile
    belongs_to :architect_agent, AgentProfile
    belongs_to :designer_agent, AgentProfile
    belongs_to :memory_agent, AgentProfile

    has_many :sources, HydraX.Product.Source
    has_many :insights, HydraX.Product.Insight
    has_many :requirements, HydraX.Product.Requirement
    has_many :product_conversations, HydraX.Product.ProductConversation

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(project, attrs) do
    project
    |> cast(attrs, [
      :name,
      :slug,
      :description,
      :status,
      :metadata,
      :researcher_agent_id,
      :strategist_agent_id,
      :architect_agent_id,
      :designer_agent_id,
      :memory_agent_id
    ])
    |> validate_required([:name, :slug, :status, :researcher_agent_id, :strategist_agent_id])
    |> validate_format(:slug, ~r/^[a-z0-9\-]+$/)
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint(:slug)
    |> foreign_key_constraint(:researcher_agent_id)
    |> foreign_key_constraint(:strategist_agent_id)
    |> foreign_key_constraint(:architect_agent_id)
    |> foreign_key_constraint(:designer_agent_id)
    |> foreign_key_constraint(:memory_agent_id)
  end
end
