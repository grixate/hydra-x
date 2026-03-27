defmodule HydraXWeb.ProductChannelAuth do
  @moduledoc false

  def authorize(socket) do
    if socket.assigns[:operator_authenticated] do
      :ok
    else
      {:error, "unauthorized"}
    end
  end

  def allow_sandbox(socket) do
    case socket.assigns[:phoenix_ecto_sandbox] do
      nil ->
        :ok

      metadata ->
        Phoenix.Ecto.SQL.Sandbox.allow(metadata, Ecto.Adapters.SQL.Sandbox)
    end
  end
end
