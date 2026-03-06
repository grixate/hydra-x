defmodule HydraX.Tools.Reply do
  @behaviour HydraX.Tool

  @impl true
  def name, do: "reply"

  @impl true
  def description, do: "Formats a final assistant reply"

  @impl true
  def execute(params, _context) do
    {:ok, %{reply: Map.get(params, :reply) || Map.get(params, "reply", "")}}
  end
end
