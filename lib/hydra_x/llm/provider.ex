defmodule HydraX.LLM.Provider do
  @moduledoc """
  Behaviour for LLM providers.

  The `complete/1` request map may include:
  - `:messages` — conversation messages
  - `:tools` — list of tool schemas (optional)
  - `:provider_config` — provider configuration
  - Other context keys (`:bulletin`, `:tool_results`, `:analysis`)

  Returns:
  - `{:ok, response}` where response includes:
    - `:content` — text response (may be nil if only tool calls)
    - `:tool_calls` — list of `%{id, name, arguments}` (may be nil/empty)
    - `:stop_reason` — "end_turn", "tool_use", etc.
    - `:provider` — provider name string
  - `{:error, term()}`

  ## Streaming

  `complete_stream/2` is an optional callback for streaming responses.
  The caller process receives:
  - `{:chunk, ref, text_delta}` — text token
  - `{:done, ref, final_response}` — stream complete, final_response is same shape as `complete/1`'s ok value
  - `{:stream_error, ref, reason}` — stream failed
  """

  @callback complete(map()) ::
              {:ok,
               %{
                 content: String.t() | nil,
                 tool_calls: [map()] | nil,
                 stop_reason: String.t(),
                 provider: String.t()
               }}
              | {:error, term()}

  @callback complete_stream(map(), pid()) ::
              {:ok, reference()} | {:error, term()}

  @callback capabilities() :: %{
              optional(:tool_calls) => boolean(),
              optional(:streaming) => boolean(),
              optional(:system_prompt) => boolean(),
              optional(:fallbacks) => boolean(),
              optional(:mock) => boolean()
            }

  @callback healthcheck(map() | nil, keyword()) ::
              {:ok, %{status: atom(), detail: String.t(), capabilities: map()}}
              | {:error, term()}

  @optional_callbacks [complete_stream: 2, capabilities: 0, healthcheck: 2]
end
