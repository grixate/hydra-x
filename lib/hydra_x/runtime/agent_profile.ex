defmodule HydraX.Runtime.AgentProfile do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(active paused archived)

  schema "agent_profiles" do
    field :name, :string
    field :slug, :string
    field :status, :string, default: "active"
    field :workspace_root, :string
    field :description, :string
    field :is_default, :boolean, default: false
    field :last_started_at, :utc_datetime_usec
    field :runtime_state, :map, default: %{}

    has_many :conversations, HydraX.Runtime.Conversation, foreign_key: :agent_id
    has_many :memories, HydraX.Memory.Entry, foreign_key: :agent_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(agent, attrs) do
    agent
    |> cast(attrs, [
      :name,
      :slug,
      :status,
      :workspace_root,
      :description,
      :is_default,
      :last_started_at,
      :runtime_state
    ])
    |> validate_required([:name, :slug, :workspace_root])
    |> validate_format(:slug, ~r/^[a-z0-9\-]+$/)
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint(:slug)
  end
end
