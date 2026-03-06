defmodule HydraX.Telemetry.Store do
  @moduledoc false
  use GenServer

  @events [
    {[:hydra_x, :provider, :request], :provider},
    {[:hydra_x, :budget, :event], :budget},
    {[:hydra_x, :tool, :execution], :tool},
    {[:hydra_x, :gateway, :delivery], :gateway},
    {[:hydra_x, :scheduler, :job], :scheduler}
  ]

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def snapshot do
    GenServer.call(__MODULE__, :snapshot)
  end

  @impl true
  def init(_state) do
    Enum.each(@events, fn {event, namespace} ->
      :telemetry.attach(
        handler_id(namespace),
        event,
        &__MODULE__.handle_telemetry/4,
        {self(), namespace}
      )
    end)

    {:ok, initial_state()}
  end

  @impl true
  def handle_call(:snapshot, _from, state), do: {:reply, state, state}

  @impl true
  def handle_info({:telemetry_event, namespace, metadata}, state) do
    {:noreply, bump_counter(state, namespace, metadata)}
  end

  @impl true
  def terminate(_reason, _state) do
    Enum.each(@events, fn {_event, namespace} ->
      :telemetry.detach(handler_id(namespace))
    end)

    :ok
  end

  def handle_telemetry(_event, _measurements, metadata, {pid, namespace}) do
    send(pid, {:telemetry_event, namespace, metadata})
  end

  defp initial_state do
    %{
      provider: %{},
      budget: %{},
      tool: %{},
      gateway: %{},
      scheduler: %{}
    }
  end

  defp handler_id(namespace), do: "hydra-x-telemetry-store-#{namespace}"

  defp bump_counter(state, :provider, metadata) do
    bump_nested_counter(state, [
      :provider,
      bucket_key(metadata[:provider]),
      status_key(metadata[:status])
    ])
  end

  defp bump_counter(state, :budget, metadata) do
    update_in(state, [:budget, status_key(metadata[:status])], &((&1 || 0) + 1))
  end

  defp bump_counter(state, :tool, metadata) do
    bump_nested_counter(state, [:tool, bucket_key(metadata[:tool]), status_key(metadata[:status])])
  end

  defp bump_counter(state, :gateway, metadata) do
    bump_nested_counter(state, [
      :gateway,
      bucket_key(metadata[:channel]),
      status_key(metadata[:status])
    ])
  end

  defp bump_counter(state, :scheduler, metadata) do
    bump_nested_counter(state, [
      :scheduler,
      bucket_key(metadata[:kind]),
      status_key(metadata[:status])
    ])
  end

  defp bucket_key(nil), do: "unknown"
  defp bucket_key(value) when is_atom(value), do: Atom.to_string(value)
  defp bucket_key(value), do: to_string(value)

  defp status_key(nil), do: "unknown"
  defp status_key(value) when is_atom(value), do: Atom.to_string(value)
  defp status_key(value), do: to_string(value)

  defp bump_nested_counter(state, [root, bucket, status]) do
    current =
      state
      |> Map.get(root, %{})
      |> Map.get(bucket, %{})
      |> Map.get(status, 0)

    state
    |> update_in(
      [root],
      &Map.put(&1 || %{}, bucket, Map.put(Map.get(&1 || %{}, bucket, %{}), status, current + 1))
    )
  end
end
