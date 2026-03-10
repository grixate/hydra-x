defmodule HydraX.Gateway.Adapters.Webchat do
  @moduledoc """
  Public browser webchat adapter implementing the Gateway.Adapter behaviour.
  """

  @behaviour HydraX.Gateway.Adapter

  @impl true
  def connect(config) do
    {:ok,
     %{
       enabled: Map.get(config, "enabled", false),
       title: Map.get(config, "title"),
       subtitle: Map.get(config, "subtitle"),
       welcome_prompt: Map.get(config, "welcome_prompt"),
       composer_placeholder: Map.get(config, "composer_placeholder")
     }}
  end

  @impl true
  def handle_event(event, state) do
    case normalize_inbound(event) do
      {:ok, messages} -> {:messages, messages, state}
      {:error, _reason} -> {:messages, [], state}
    end
  end

  @impl true
  def send_response(%{content: _content, external_ref: external_ref}, _state) do
    {:ok, %{channel: "webchat", external_ref: external_ref, streaming: true}}
  end

  def send_response(%{text: _content, session_id: external_ref}, _state) do
    {:ok, %{channel: "webchat", external_ref: external_ref, streaming: true}}
  end

  @impl true
  def normalize_inbound(%{"session_id" => session_id, "content" => content} = payload)
      when is_binary(session_id) and is_binary(content) do
    {:ok,
     [
       %{
         channel: "webchat",
         external_ref: session_id,
         content: content,
         metadata: %{
           raw: payload,
           browser_session: session_id,
           source: "webchat"
         }
       }
     ]}
  end

  def normalize_inbound(_payload), do: {:error, :invalid_webchat_payload}

  @impl true
  def deliver(message, state) do
    send_response(message, state)
  end

  @impl true
  def health(state) do
    %{
      channel: "webchat",
      configured: true,
      enabled: Map.get(state, :enabled, false),
      supports_threads: false,
      supports_rich_formatting: false,
      supports_attachments: false,
      supports_streaming: true
    }
  end

  @impl true
  def sync_status(state) do
    {:ok,
     %{
       title: state.title,
       subtitle: state.subtitle,
       enabled: state.enabled
     }}
  end

  @impl true
  def capabilities do
    %{
      channel: "webchat",
      inbound: [:text],
      outbound: [:text],
      threads: false,
      attachments: false,
      rich_formatting: false,
      streaming: true
    }
  end

  @impl true
  def format_message(%{content: content, external_ref: external_ref}, _state) do
    %{text: content, session_id: external_ref}
  end
end
