defmodule HydraX.Runtime.ToolPolicy do
  use Ecto.Schema
  import Ecto.Changeset

  schema "tool_policies" do
    field :scope, :string, default: "default"
    field :workspace_read_enabled, :boolean, default: true
    field :http_fetch_enabled, :boolean, default: true
    field :shell_command_enabled, :boolean, default: true
    field :shell_allowlist_csv, :string, default: ""
    field :http_allowlist_csv, :string, default: ""

    belongs_to :agent, HydraX.Runtime.AgentProfile

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(policy, attrs) do
    policy
    |> cast(attrs, [
      :scope,
      :agent_id,
      :workspace_read_enabled,
      :http_fetch_enabled,
      :shell_command_enabled,
      :shell_allowlist_csv,
      :http_allowlist_csv
    ])
    |> validate_required([:scope])
    |> unique_constraint([:scope, :agent_id])
  end
end
