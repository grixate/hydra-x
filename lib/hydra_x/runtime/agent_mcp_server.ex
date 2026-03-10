defmodule HydraX.Runtime.AgentMCPServer do
  use Ecto.Schema
  import Ecto.Changeset

  schema "agent_mcp_servers" do
    field :enabled, :boolean, default: true
    field :metadata, :map, default: %{}

    belongs_to :agent, HydraX.Runtime.AgentProfile
    belongs_to :mcp_server_config, HydraX.Runtime.MCPServerConfig

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(binding, attrs) do
    binding
    |> cast(attrs, [:agent_id, :mcp_server_config_id, :enabled, :metadata])
    |> validate_required([:agent_id, :mcp_server_config_id])
    |> unique_constraint([:agent_id, :mcp_server_config_id],
      name: :agent_mcp_servers_agent_id_mcp_server_config_id_index
    )
  end
end
