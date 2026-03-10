defmodule HydraX.Runtime.MCPServerConfig do
  use Ecto.Schema
  import Ecto.Changeset

  @transports ~w(stdio http)

  schema "mcp_server_configs" do
    field :name, :string
    field :transport, :string, default: "stdio"
    field :command, :string
    field :args_csv, :string
    field :cwd, :string
    field :url, :string
    field :healthcheck_path, :string, default: "/health"
    field :auth_token, :string
    field :enabled, :boolean, default: true
    field :retry_limit, :integer, default: 2
    field :metadata, :map, default: %{}

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(config, attrs) do
    config
    |> cast(attrs, [
      :name,
      :transport,
      :command,
      :args_csv,
      :cwd,
      :url,
      :healthcheck_path,
      :auth_token,
      :enabled,
      :retry_limit,
      :metadata
    ])
    |> put_default(:retry_limit, 2)
    |> put_default(:healthcheck_path, "/health")
    |> put_default(:enabled, true)
    |> validate_required([:name, :transport])
    |> validate_inclusion(:transport, @transports)
    |> validate_number(:retry_limit, greater_than_or_equal_to: 0)
    |> validate_transport_fields()
  end

  defp put_default(changeset, field, value) do
    case get_field(changeset, field) do
      nil -> put_change(changeset, field, value)
      _ -> changeset
    end
  end

  defp validate_transport_fields(changeset) do
    case get_field(changeset, :transport) do
      "stdio" ->
        changeset
        |> validate_required([:command])

      "http" ->
        changeset
        |> validate_required([:url])

      _ ->
        changeset
    end
  end
end
