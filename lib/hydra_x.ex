defmodule HydraX do
  @moduledoc """
  Hydra-X is a single-node Elixir agent runtime with a Phoenix control plane.
  """

  @spec version() :: String.t()
  def version, do: Application.spec(:hydra_x, :vsn) |> to_string()
end
