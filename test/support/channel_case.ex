defmodule HydraXWeb.ChannelCase do
  use ExUnit.CaseTemplate

  require Phoenix.ChannelTest

  @endpoint HydraXWeb.Endpoint

  using do
    quote do
      use HydraXWeb, :verified_routes

      import Phoenix.ChannelTest
      import HydraXWeb.ChannelCase

      @endpoint HydraXWeb.Endpoint
    end
  end

  setup tags do
    pid = HydraX.DataCase.setup_sandbox(tags)

    metadata =
      HydraX.Repo
      |> Phoenix.Ecto.SQL.Sandbox.metadata_for(pid)
      |> Phoenix.Ecto.SQL.Sandbox.encode_metadata()

    socket =
      Phoenix.ChannelTest.socket(HydraXWeb.UserSocket, nil, %{
        operator_authenticated: true,
        phoenix_ecto_sandbox: metadata
      })

    {:ok, socket: socket, phoenix_ecto_sandbox: metadata}
  end
end
