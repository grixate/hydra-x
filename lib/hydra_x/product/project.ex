defmodule HydraX.Product.Project do
  use Ecto.Schema
  import Ecto.Changeset

  alias HydraX.Runtime.AgentProfile

  @statuses ~w(active archived)
  @trust_levels ~w(cautious standard autonomous)
  @onboarding_states ~w(pending in_progress completed skipped)

  def onboarding_states, do: @onboarding_states

  schema "projects" do
    field :name, :string
    field :slug, :string
    field :description, :string
    field :status, :string, default: "active"
    field :trust_level, :string, default: "standard"
    field :metadata, :map, default: %{}

    field :onboarding_state, :string, default: "pending"
    field :onboarded_at, :utc_datetime_usec
    field :onboarding_skipped_at, :utc_datetime_usec

    belongs_to :workspace, HydraX.Accounts.Workspace, type: :binary_id

    belongs_to :researcher_agent, AgentProfile
    belongs_to :strategist_agent, AgentProfile
    belongs_to :architect_agent, AgentProfile
    belongs_to :designer_agent, AgentProfile
    belongs_to :memory_agent, AgentProfile
    belongs_to :coder_agent, AgentProfile

    has_many :sources, HydraX.Product.Source
    has_many :product_conversations, HydraX.Product.ProductConversation
    has_many :board_sessions, HydraX.Product.BoardSession

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(project, attrs) do
    project
    |> cast(attrs, [
      :name,
      :slug,
      :description,
      :status,
      :trust_level,
      :metadata,
      :onboarding_state,
      :onboarded_at,
      :onboarding_skipped_at,
      :workspace_id,
      :researcher_agent_id,
      :strategist_agent_id,
      :architect_agent_id,
      :designer_agent_id,
      :memory_agent_id,
      :coder_agent_id
    ])
    |> validate_required([:name, :slug, :status, :researcher_agent_id, :strategist_agent_id])
    |> validate_format(:slug, ~r/^[a-z0-9\-]+$/)
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:trust_level, @trust_levels)
    |> validate_inclusion(:onboarding_state, @onboarding_states)
    |> unique_constraint(:slug)
    |> foreign_key_constraint(:researcher_agent_id)
    |> foreign_key_constraint(:strategist_agent_id)
    |> foreign_key_constraint(:architect_agent_id)
    |> foreign_key_constraint(:designer_agent_id)
    |> foreign_key_constraint(:memory_agent_id)
  end
end
