defmodule HydraX.ProcessRegistry do
  @moduledoc false

  @spec via(term()) :: {:via, Registry, {module(), term()}}
  def via(key), do: {:via, Registry, {__MODULE__, key}}
end
