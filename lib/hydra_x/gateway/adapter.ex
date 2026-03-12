defmodule HydraX.Gateway.Adapter do
  @moduledoc """
  Behaviour for external channel adapters.

  Older callbacks are retained for backward compatibility.
  Newer runtime code should prefer `normalize_inbound/1`, `deliver/2`,
  `health/1`, `sync_status/1`, `capabilities/0`, and `format_message/2`.
  """

  @callback connect(map()) :: {:ok, term()} | {:error, term()}
  @callback handle_event(term(), term()) :: {:messages, [map()], term()}
  @callback send_response(map(), term()) :: :ok | {:ok, map()} | {:error, term()}
  @callback normalize_inbound(term()) :: {:ok, [map()]} | {:error, term()}
  @callback deliver(map(), term()) :: {:ok, map()} | {:error, term()}
  @callback health(term()) :: map()
  @callback sync_status(term()) :: {:ok, map()} | {:error, term()}
  @callback capabilities() :: map()
  @callback format_message(map(), term()) :: map()
  @callback deliver_stream(map(), term()) :: {:ok, map()} | {:error, term()}

  @optional_callbacks normalize_inbound: 1,
                      deliver: 2,
                      deliver_stream: 2,
                      health: 1,
                      sync_status: 1,
                      capabilities: 0,
                      format_message: 2
end
