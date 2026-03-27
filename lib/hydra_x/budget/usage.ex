defmodule HydraX.Budget.Usage do
  use Ecto.Schema
  import Ecto.Changeset

  schema "hx_budget_usages" do
    field :scope, :string
    field :tokens_in, :integer, default: 0
    field :tokens_out, :integer, default: 0
    field :metadata, :map, default: %{}

    belongs_to :agent, HydraX.Runtime.AgentProfile
    belongs_to :conversation, HydraX.Runtime.Conversation

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(usage, attrs) do
    usage
    |> cast(attrs, [:agent_id, :conversation_id, :scope, :tokens_in, :tokens_out, :metadata])
    |> validate_required([:agent_id, :scope, :tokens_in, :tokens_out])
    |> validate_number(:tokens_in, greater_than_or_equal_to: 0)
    |> validate_number(:tokens_out, greater_than_or_equal_to: 0)
    |> assoc_constraint(:agent)
    |> assoc_constraint(:conversation)
  end
end
