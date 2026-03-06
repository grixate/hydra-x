defmodule HydraX.Budget.Policy do
  use Ecto.Schema
  import Ecto.Changeset

  @actions ~w(reject warn)

  schema "budget_policies" do
    field :daily_limit, :integer, default: 20_000
    field :conversation_limit, :integer, default: 4_000
    field :soft_warning_at, :float, default: 0.8
    field :hard_limit_action, :string, default: "reject"
    field :enabled, :boolean, default: true

    belongs_to :agent, HydraX.Runtime.AgentProfile

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(policy, attrs) do
    policy
    |> cast(attrs, [
      :agent_id,
      :daily_limit,
      :conversation_limit,
      :soft_warning_at,
      :hard_limit_action,
      :enabled
    ])
    |> validate_required([
      :agent_id,
      :daily_limit,
      :conversation_limit,
      :soft_warning_at,
      :hard_limit_action
    ])
    |> validate_number(:daily_limit, greater_than: 0)
    |> validate_number(:conversation_limit, greater_than: 0)
    |> validate_number(:soft_warning_at, greater_than: 0.0, less_than: 1.0)
    |> validate_inclusion(:hard_limit_action, @actions)
    |> assoc_constraint(:agent)
    |> unique_constraint(:agent_id)
  end
end
