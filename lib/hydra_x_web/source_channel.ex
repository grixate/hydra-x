defmodule HydraXWeb.SourceChannel do
  use HydraXWeb, :channel

  alias HydraX.Product
  alias HydraX.Product.PubSub, as: ProductPubSub
  alias HydraXWeb.ProductChannelAuth
  alias HydraXWeb.ProductPayload
  alias HydraXWeb.ProductRealtimePayload

  @impl true
  def join("source:" <> raw_id, _params, socket) do
    with :ok <- ProductChannelAuth.authorize(socket),
         :ok <- ProductChannelAuth.allow_sandbox(socket),
         source <- Product.get_source!(String.to_integer(raw_id)) do
      Phoenix.PubSub.subscribe(HydraX.PubSub, ProductPubSub.source_topic(source.id))

      {:ok,
       %{
         source: ProductPayload.source_json(source, true)
       }, assign(socket, :source_id, source.id)}
    else
      {:error, reason} -> {:error, %{reason: reason}}
    end
  rescue
    Ecto.NoResultsError -> {:error, %{reason: "not_found"}}
  end

  @impl true
  def handle_info({:product_source_event, event, payload}, socket)
      when event in ["progress", "completed", "failed", "deleted"] do
    push(socket, event, ProductRealtimePayload.source_event_json(event, payload))
    {:noreply, socket}
  end

  def handle_info(_message, socket), do: {:noreply, socket}
end
