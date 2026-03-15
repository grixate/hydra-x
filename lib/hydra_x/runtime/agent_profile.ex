defmodule HydraX.Runtime.AgentProfile do
  use Ecto.Schema
  import Ecto.Changeset

  alias HydraX.Runtime.Autonomy

  @statuses ~w(active paused archived)

  schema "agent_profiles" do
    field :name, :string
    field :slug, :string
    field :status, :string, default: "active"
    field :role, :string, default: "operator"
    field :workspace_root, :string
    field :description, :string
    field :is_default, :boolean, default: false
    field :last_started_at, :utc_datetime_usec
    field :runtime_state, :map, default: %{}
    field :capability_profile, :map, default: %{}

    has_many :conversations, HydraX.Runtime.Conversation, foreign_key: :agent_id
    has_many :memories, HydraX.Memory.Entry, foreign_key: :agent_id
    has_many :assigned_work_items, HydraX.Runtime.WorkItem, foreign_key: :assigned_agent_id
    has_many :delegated_work_items, HydraX.Runtime.WorkItem, foreign_key: :delegated_by_agent_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(agent, attrs) do
    agent
    |> cast(attrs, [
      :name,
      :slug,
      :status,
      :role,
      :workspace_root,
      :description,
      :is_default,
      :last_started_at,
      :runtime_state,
      :capability_profile
    ])
    |> validate_required([:name, :slug, :workspace_root])
    |> validate_format(:slug, ~r/^[a-z0-9\-]+$/)
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:role, Autonomy.roles())
    |> unique_constraint(:slug)
  end
end
