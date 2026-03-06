defmodule HydraX.Gateway.Adapter do
  @moduledoc """
  Behaviour for external channel adapters.
  """

  @callback connect(map()) :: {:ok, term()} | {:error, term()}
  @callback handle_event(term(), term()) :: {:messages, [map()], term()}
  @callback send_response(map(), term()) :: :ok | {:ok, map()} | {:error, term()}
end
