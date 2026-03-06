defmodule HydraX.Tool do
  @moduledoc """
  Behaviour for Hydra-X tools.
  """

  @callback name() :: String.t()
  @callback description() :: String.t()
  @callback execute(map(), map()) :: {:ok, map()} | {:error, term()}
end
