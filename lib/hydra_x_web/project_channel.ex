defmodule HydraXWeb.ProjectChannel do
  use HydraXWeb, :channel

  alias HydraX.Product
  alias HydraX.Product.PubSub, as: ProductPubSub
  alias HydraXWeb.ProductChannelAuth
  alias HydraXWeb.ProductRealtimePayload

  @impl true
  def join("project:" <> raw_id, _params, socket) do
    with :ok <- ProductChannelAuth.authorize(socket),
         :ok <- ProductChannelAuth.allow_sandbox(socket),
         project <- Product.get_project!(String.to_integer(raw_id)) do
      Phoenix.PubSub.subscribe(HydraX.PubSub, ProductPubSub.project_topic(project.id))

      {:ok, ProductRealtimePayload.project_join_json(project, Product.project_counts(project.id)),
       assign(socket, :project_id, project.id)}
    else
      {:error, reason} -> {:error, %{reason: reason}}
    end
  rescue
    Ecto.NoResultsError -> {:error, %{reason: "not_found"}}
  end

  @impl true
  def handle_info({:product_project_event, event, payload}, socket) do
    push(socket, event, ProductRealtimePayload.project_event_json(event, payload))
    {:noreply, socket}
  end

  def handle_info(_message, socket), do: {:noreply, socket}
end
