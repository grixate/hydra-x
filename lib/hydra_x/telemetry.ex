defmodule HydraX.Telemetry do
  @moduledoc """
  Emits runtime telemetry for Hydra-X-specific operations.
  """

  def provider_request(status, provider, metadata \\ %{}) do
    execute(
      [:hydra_x, :provider, :request],
      %{count: 1},
      Map.merge(%{status: status, provider: provider}, metadata)
    )
  end

  def budget_event(status, metadata \\ %{}) do
    execute([:hydra_x, :budget, :event], %{count: 1}, Map.put(metadata, :status, status))
  end

  def tool_execution(tool, status, metadata \\ %{}) do
    execute(
      [:hydra_x, :tool, :execution],
      %{count: 1},
      Map.merge(%{tool: tool, status: status}, metadata)
    )
  end

  def gateway_delivery(channel, status, metadata \\ %{}) do
    execute(
      [:hydra_x, :gateway, :delivery],
      %{count: 1},
      Map.merge(%{channel: channel, status: status}, metadata)
    )
  end

  def scheduler_job(kind, status, metadata \\ %{}) do
    execute(
      [:hydra_x, :scheduler, :job],
      %{count: 1},
      Map.merge(%{kind: kind, status: status}, metadata)
    )
  end

  defp execute(event, measurements, metadata) do
    :telemetry.execute(event, measurements, metadata)
  end
end
