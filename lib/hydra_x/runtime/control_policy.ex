defmodule HydraX.Runtime.ControlPolicy do
  use Ecto.Schema
  import Ecto.Changeset

  schema "control_policies" do
    field :scope, :string, default: "default"
    field :require_recent_auth_for_sensitive_actions, :boolean, default: true
    field :recent_auth_window_minutes, :integer, default: 15
    field :interactive_delivery_channels_csv, :string, default: "telegram,discord,slack,webchat"
    field :job_delivery_channels_csv, :string, default: "telegram,discord,slack,webchat"
    field :ingest_roots_csv, :string, default: "ingest"

    belongs_to :agent, HydraX.Runtime.AgentProfile

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(policy, attrs) do
    policy
    |> cast(attrs, [
      :scope,
      :agent_id,
      :require_recent_auth_for_sensitive_actions,
      :recent_auth_window_minutes,
      :interactive_delivery_channels_csv,
      :job_delivery_channels_csv,
      :ingest_roots_csv
    ])
    |> validate_required([:scope, :recent_auth_window_minutes])
    |> validate_number(:recent_auth_window_minutes,
      greater_than_or_equal_to: 1,
      less_than_or_equal_to: 1_440
    )
    |> unique_constraint([:scope, :agent_id])
  end
end
