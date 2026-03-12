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
       composer_placeholder: Map.get(config, "composer_placeholder"),
       allow_anonymous_messages: Map.get(config, "allow_anonymous_messages", true),
       attachments_enabled: Map.get(config, "attachments_enabled", true),
       max_attachment_count: Map.get(config, "max_attachment_count", 3),
       max_attachment_size_kb: Map.get(config, "max_attachment_size_kb", 2_048),
       session_max_age_minutes: Map.get(config, "session_max_age_minutes", 24 * 60),
       session_idle_timeout_minutes: Map.get(config, "session_idle_timeout_minutes", 120)
     }}
  end

  @impl true
  def handle_event(event, state) do
    case normalize_inbound(event, state) do
      {:ok, messages} -> {:messages, messages, state}
      {:error, _reason} -> {:messages, [], state}
    end
  end

  @impl true
  def send_response(%{content: _content, external_ref: external_ref}, _state) do
    publish_session_event(external_ref, {:webchat_delivery, external_ref})
    {:ok, %{channel: "webchat", external_ref: external_ref, streaming: true}}
  end

  def send_response(%{text: _content, session_id: external_ref}, _state) do
    publish_session_event(external_ref, {:webchat_delivery, external_ref})
    {:ok, %{channel: "webchat", external_ref: external_ref, streaming: true}}
  end

  @impl true
  def normalize_inbound(%{"session_id" => _session_id} = payload) do
    normalize_inbound(payload, %{
      allow_anonymous_messages: true,
      attachments_enabled: true,
      max_attachment_count: 3,
      max_attachment_size_kb: 2_048
    })
  end

  def normalize_inbound(_payload), do: {:error, :invalid_webchat_payload}

  def normalize_inbound(
        %{"session_id" => session_id} = payload,
        state
      )
      when is_binary(session_id) do
    attachments =
      payload
      |> Map.get("attachments", [])
      |> normalize_attachments(state)

    content =
      payload
      |> Map.get("content", "")
      |> normalize_content(attachments)

    display_name =
      payload
      |> Map.get("display_name")
      |> normalize_display_name()

    cond do
      content in [nil, ""] ->
        {:error, :invalid_webchat_payload}

      display_name in [nil, ""] and not Map.get(state, :allow_anonymous_messages, true) ->
        {:error, :webchat_identity_required}

      true ->
        {:ok,
         [
           %{
             channel: "webchat",
             external_ref: session_id,
             content: content,
             metadata: %{
               raw: payload,
               browser_session: session_id,
               source: "webchat",
               attachments: attachments,
               display_name: display_name,
               anonymous: display_name in [nil, ""]
             }
           }
         ]}
    end
  end

  def normalize_inbound(_payload, _state), do: {:error, :invalid_webchat_payload}

  @impl true
  def deliver(message, state) do
    send_response(message, state)
  end

  @impl true
  def deliver_stream(%{content: content, external_ref: external_ref} = message, _state) do
    chunk_count = Map.get(message, :chunk_count, 0)

    publish_session_event(
      external_ref,
      {:webchat_stream_preview, external_ref, content, chunk_count}
    )

    {:ok,
     %{
       channel: "webchat",
       external_ref: external_ref,
       streaming: true,
       transport: "session_pubsub",
       topic: session_topic(external_ref)
     }}
  end

  @impl true
  def health(state) do
    %{
      channel: "webchat",
      configured: true,
      enabled: Map.get(state, :enabled, false),
      supports_threads: false,
      supports_rich_formatting: false,
      supports_attachments: true,
      supports_streaming: true,
      anonymous_access: Map.get(state, :allow_anonymous_messages, true),
      session_max_age_minutes: Map.get(state, :session_max_age_minutes, 24 * 60),
      session_idle_timeout_minutes: Map.get(state, :session_idle_timeout_minutes, 120),
      attachments_enabled: Map.get(state, :attachments_enabled, true)
    }
  end

  @impl true
  def sync_status(state) do
    {:ok,
     %{
       title: state.title,
       subtitle: state.subtitle,
       enabled: state.enabled,
       allow_anonymous_messages: state.allow_anonymous_messages,
       attachments_enabled: state.attachments_enabled
     }}
  end

  @impl true
  def capabilities do
    %{
      channel: "webchat",
      inbound: [:text, :attachment],
      outbound: [:text],
      threads: false,
      attachments: true,
      rich_formatting: false,
      streaming: true,
      stream_transport: "session_pubsub"
    }
  end

  @impl true
  def format_message(%{content: content, external_ref: external_ref}, _state) do
    %{text: content, session_id: external_ref}
  end

  def session_topic(session_ref) when is_binary(session_ref) and session_ref != "" do
    "webchat:session:" <> session_ref
  end

  defp normalize_content(content, attachments) when is_binary(content) do
    trimmed = String.trim(content)
    if trimmed == "", do: attachment_summary(attachments), else: trimmed
  end

  defp normalize_content(_content, attachments), do: attachment_summary(attachments)

  defp normalize_display_name(nil), do: nil

  defp normalize_display_name(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> String.slice(trimmed, 0, 80)
    end
  end

  defp normalize_display_name(_value), do: nil

  defp normalize_attachments(attachments, state) when is_list(attachments) do
    if Map.get(state, :attachments_enabled, true) do
      attachments
      |> Enum.take(Map.get(state, :max_attachment_count, 3))
      |> Enum.map(&normalize_attachment(&1, state))
      |> Enum.reject(&is_nil/1)
    else
      []
    end
  end

  defp normalize_attachments(_attachments, _state), do: []

  defp normalize_attachment(%{} = attachment, state) do
    size = attachment["size"] || attachment[:size] || 0
    max_bytes = Map.get(state, :max_attachment_size_kb, 2_048) * 1_024

    if is_integer(size) and size > max_bytes do
      nil
    else
      %{
        "kind" => attachment["kind"] || attachment[:kind] || "upload",
        "id" => attachment["id"] || attachment[:id],
        "file_name" => attachment["file_name"] || attachment[:file_name],
        "content_type" => attachment["content_type"] || attachment[:content_type],
        "size" => size,
        "upload_ref" => attachment["upload_ref"] || attachment[:upload_ref],
        "source_url" => attachment["source_url"] || attachment[:source_url]
      }
      |> Enum.reject(fn {_key, value} -> value in [nil, "", 0] end)
      |> Map.new()
    end
  end

  defp normalize_attachment(_attachment, _state), do: nil

  defp attachment_summary([]), do: nil

  defp attachment_summary(attachments) do
    kinds =
      attachments
      |> Enum.map(&(&1["content_type"] || &1["kind"] || "attachment"))
      |> Enum.uniq()
      |> Enum.join(", ")

    "[Webchat attachments: #{kinds}]"
  end

  defp publish_session_event(session_ref, event)
       when is_binary(session_ref) and session_ref != "" do
    Phoenix.PubSub.broadcast(HydraX.PubSub, session_topic(session_ref), event)
  end
end
