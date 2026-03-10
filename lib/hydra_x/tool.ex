defmodule HydraX.Tool do
  @moduledoc """
  Behaviour for Hydra-X tools.
  """

  @callback name() :: String.t()
  @callback description() :: String.t()
  @callback tool_schema() :: map()
  @callback execute(map(), map()) :: {:ok, map()} | {:error, term()}
  @callback safety_classification() :: String.t()
  @callback result_summary(map()) :: String.t()

  @optional_callbacks safety_classification: 0, result_summary: 1
end
