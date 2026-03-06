defmodule HydraX.LLM.Provider do
  @moduledoc """
  Behaviour for LLM providers.
  """

  @callback complete(map()) ::
              {:ok, %{content: String.t(), provider: String.t()}} | {:error, term()}
end
