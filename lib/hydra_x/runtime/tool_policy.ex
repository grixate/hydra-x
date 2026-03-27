defmodule HydraX.Runtime.ToolPolicy do
  use Ecto.Schema
  import Ecto.Changeset

  schema "hx_tool_policies" do
    field :scope, :string, default: "default"
    field :workspace_list_enabled, :boolean, default: true
    field :workspace_read_enabled, :boolean, default: true
    field :workspace_write_enabled, :boolean, default: false
    field :http_fetch_enabled, :boolean, default: true
    field :browser_automation_enabled, :boolean, default: false
    field :web_search_enabled, :boolean, default: true
    field :shell_command_enabled, :boolean, default: true
    field :shell_allowlist_csv, :string, default: ""
    field :http_allowlist_csv, :string, default: ""
    field :workspace_write_channels_csv, :string, default: ""
    field :http_fetch_channels_csv, :string, default: ""
    field :browser_automation_channels_csv, :string, default: ""
    field :web_search_channels_csv, :string, default: ""
    field :shell_command_channels_csv, :string, default: ""

    belongs_to :agent, HydraX.Runtime.AgentProfile

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(policy, attrs) do
    policy
    |> cast(attrs, [
      :scope,
      :agent_id,
      :workspace_list_enabled,
      :workspace_read_enabled,
      :workspace_write_enabled,
      :http_fetch_enabled,
      :browser_automation_enabled,
      :web_search_enabled,
      :shell_command_enabled,
      :shell_allowlist_csv,
      :http_allowlist_csv,
      :workspace_write_channels_csv,
      :http_fetch_channels_csv,
      :browser_automation_channels_csv,
      :web_search_channels_csv,
      :shell_command_channels_csv
    ])
    |> validate_required([:scope])
    |> unique_constraint([:scope, :agent_id])
  end
end
