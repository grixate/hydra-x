defmodule HydraXWeb.WebchatLive do
  use HydraXWeb, :live_view

  alias HydraX.Gateway
  alias HydraX.Runtime

  @impl true
  def mount(_params, session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(HydraX.PubSub, "conversations")
      Phoenix.PubSub.subscribe(HydraX.PubSub, "conversations:stream")
    end

    config =
      Runtime.enabled_webchat_config() || List.first(Runtime.list_webchat_configs()) ||
        %Runtime.WebchatConfig{}

    session_ref = webchat_session_ref(session)
    session_state = webchat_session_state(session, config)
    conversation = webchat_conversation(config, session_ref)
    channel_state = conversation && Runtime.conversation_channel_state(conversation.id)

    socket =
      socket
      |> assign(:page_title, config.title || "Hydra-X Webchat")
      |> assign(:config, config)
      |> assign(:session_ref, session_ref)
      |> assign(:session_state, session_state)
      |> assign(:conversation, conversation)
      |> assign(:streaming_content, channel_streaming_preview(channel_state))
      |> assign(:message_form, to_form(%{"message" => ""}, as: :message))
      |> assign(
        :identity_form,
        to_form(%{"display_name" => session_state.display_name || ""}, as: :webchat_identity)
      )
      |> maybe_flash_reset_reason(session_state.reset_reason)
      |> configure_attachments(config)

    {:ok, socket}
  end

  @impl true
  def handle_event("send_message", %{"message" => %{"message" => message}}, socket) do
    config = socket.assigns.config
    message = String.trim(message || "")

    cond do
      not config.enabled ->
        {:noreply, put_flash(socket, :error, "Webchat is not enabled on this node.")}

      identity_required?(socket.assigns.session_state) ->
        {:noreply, put_flash(socket, :error, "Set a display name first.")}

      message == "" and pending_attachment_count(socket) == 0 ->
        {:noreply, put_flash(socket, :error, "Enter a message or upload an attachment first.")}

      true ->
        attachments = consume_webchat_attachments(socket)

        case Gateway.dispatch_webchat_message(%{
               "session_id" => socket.assigns.session_ref,
               "content" => message,
               "title" => config.title,
               "display_name" => socket.assigns.session_state.display_name,
               "attachments" => attachments
             }) do
          :ok ->
            conversation = webchat_conversation(config, socket.assigns.session_ref)

            {:noreply,
             socket
             |> assign(:conversation, conversation)
             |> assign(:message_form, to_form(%{"message" => ""}, as: :message))}

          {:error, :webchat_not_configured} ->
            {:noreply, put_flash(socket, :error, "Webchat is not enabled on this node.")}

          {:error, :webchat_identity_required} ->
            {:noreply,
             put_flash(socket, :error, "Webchat requires a display name before sending messages.")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Webchat failed: #{inspect(reason)}")}
        end
    end
  end

  @impl true
  def handle_info({:conversation_updated, conversation_id}, socket) do
    case socket.assigns.conversation do
      %{id: ^conversation_id} ->
        conversation = Runtime.get_conversation!(conversation_id)
        channel_state = Runtime.conversation_channel_state(conversation_id)

        {:noreply,
         socket
         |> assign(:conversation, conversation)
         |> assign(:streaming_content, channel_streaming_preview(channel_state))}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:stream_chunk, conversation_id, delta}, socket) do
    case socket.assigns.conversation do
      %{id: ^conversation_id} ->
        {:noreply,
         assign(socket, :streaming_content, (socket.assigns.streaming_content || "") <> delta)}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:stream_done, conversation_id}, socket) do
    case socket.assigns.conversation do
      %{id: ^conversation_id} ->
        {:noreply,
         socket
         |> assign(:conversation, Runtime.get_conversation!(conversation_id))
         |> assign(:streaming_content, nil)}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-[var(--hx-bg)] text-[var(--hx-ink)]">
      <div class="pointer-events-none fixed inset-0 bg-[radial-gradient(circle_at_top_left,rgba(245,110,66,0.18),transparent_28%),radial-gradient(circle_at_bottom_right,rgba(70,160,180,0.16),transparent_32%)]">
      </div>
      <div class="relative mx-auto flex min-h-screen max-w-6xl flex-col gap-8 px-4 py-8 sm:px-6 lg:px-8">
        <section class="grid gap-6 lg:grid-cols-[0.9fr_1.1fr]">
          <article class="overflow-hidden rounded-[2rem] border border-white/10 bg-black/20 p-8 shadow-[0_30px_80px_rgba(0,0,0,0.35)] backdrop-blur">
            <div class="text-xs uppercase tracking-[0.35em] text-[var(--hx-mute)]">Hydra-X</div>
            <h1 class="mt-4 font-display text-5xl leading-none">
              {@config.title || "Webchat ingress"}
            </h1>
            <p class="mt-4 max-w-xl text-base leading-7 text-[var(--hx-mute)]">
              {@config.subtitle || "A public channel into the Hydra-X runtime."}
            </p>
            <div class="mt-8 grid gap-3 sm:grid-cols-2">
              <article class="rounded-3xl border border-white/10 bg-white/5 px-5 py-4">
                <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                  Session binding
                </div>
                <div class="mt-3 text-sm text-[var(--hx-accent)]">{@session_ref}</div>
              </article>
              <article class="rounded-3xl border border-white/10 bg-white/5 px-5 py-4">
                <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                  Channel state
                </div>
                <div class="mt-3 text-sm text-[var(--hx-accent)]">
                  {if @config.enabled, do: "ready for chat", else: "disabled in setup"}
                </div>
              </article>
              <article class="rounded-3xl border border-white/10 bg-white/5 px-5 py-4">
                <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                  Session state
                </div>
                <div class="mt-3 text-sm text-[var(--hx-accent)]">
                  {conversation_state(@conversation, @streaming_content, @session_state)}
                </div>
              </article>
              <article class="rounded-3xl border border-white/10 bg-white/5 px-5 py-4">
                <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                  Turn count
                </div>
                <div class="mt-3 text-sm text-[var(--hx-accent)]">
                  {conversation_turn_count(@conversation)}
                </div>
              </article>
            </div>
            <div class="mt-8 grid gap-3 sm:grid-cols-2">
              <article class="rounded-3xl border border-white/10 bg-white/5 px-5 py-4">
                <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                  Identity policy
                </div>
                <div class="mt-3 text-sm text-[var(--hx-accent)]">
                  {identity_policy_label(@session_state)}
                </div>
              </article>
              <article class="rounded-3xl border border-white/10 bg-white/5 px-5 py-4">
                <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                  Attachment policy
                </div>
                <div class="mt-3 text-sm text-[var(--hx-accent)]">
                  {attachment_policy_label(@config)}
                </div>
              </article>
            </div>
            <div
              :if={@config.welcome_prompt not in [nil, ""]}
              class="mt-8 rounded-3xl border border-white/10 bg-[rgba(255,255,255,0.04)] px-5 py-5 text-sm leading-7 text-[var(--hx-mute)]"
            >
              {@config.welcome_prompt}
            </div>
            <div class="mt-8 rounded-3xl border border-white/10 bg-[rgba(255,255,255,0.04)] px-5 py-5">
              <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                Session controls
              </div>
              <p class="mt-3 text-sm leading-6 text-[var(--hx-mute)]">
                Max age {@config.session_max_age_minutes}m · idle timeout {@config.session_idle_timeout_minutes}m
                · identity {if @session_state.display_name,
                  do: @session_state.display_name,
                  else: "anonymous"}
              </p>
              <.form
                for={@identity_form}
                action={~p"/webchat/session"}
                method="post"
                class="mt-4 grid gap-3 sm:grid-cols-[1fr_auto]"
              >
                <.input
                  field={@identity_form[:display_name]}
                  label={
                    if @config.allow_anonymous_messages,
                      do: "Display name (optional)",
                      else: "Display name (required)"
                  }
                  placeholder="Workspace visitor"
                />
                <div class="self-end pt-2">
                  <.button>Save identity</.button>
                </div>
              </.form>
              <.form
                for={to_form(%{}, as: :webchat_session)}
                action={~p"/webchat/session"}
                method="delete"
                class="mt-3"
              >
                <button
                  type="submit"
                  class="btn btn-outline border-white/10 bg-white/5 text-white hover:bg-white/10"
                >
                  Reset session
                </button>
              </.form>
            </div>
          </article>

          <article class="flex min-h-[70vh] flex-col overflow-hidden rounded-[2rem] border border-white/10 bg-[rgba(10,14,18,0.72)] shadow-[0_30px_80px_rgba(0,0,0,0.35)] backdrop-blur">
            <div class="border-b border-white/10 px-6 py-5">
              <div class="font-mono text-xs uppercase tracking-[0.22em] text-[var(--hx-mute)]">
                Live conversation
              </div>
            </div>

            <div class="flex-1 space-y-4 overflow-y-auto px-6 py-6">
              <div
                :if={is_nil(@conversation)}
                class="rounded-3xl border border-dashed border-white/10 px-5 py-10 text-center text-sm text-[var(--hx-mute)]"
              >
                Start a message to open a session-backed Webchat conversation.
              </div>

              <div
                :for={turn <- (@conversation && @conversation.turns) || []}
                class={[
                  "max-w-[85%] rounded-[1.6rem] px-5 py-4 text-sm leading-7",
                  if(turn.role == "user",
                    do:
                      "ml-auto border border-[var(--hx-accent)]/30 bg-[rgba(245,110,66,0.14)] text-white",
                    else: "border border-white/10 bg-white/5 text-[var(--hx-mute)]"
                  )
                ]}
              >
                <div class="font-mono text-[10px] uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                  {turn_role_label(turn)}
                </div>
                <div class="mt-2 whitespace-pre-wrap">{turn.content}</div>
                <div :if={turn_attachments(turn) != []} class="mt-3 flex flex-wrap gap-2 text-xs">
                  <span
                    :for={attachment <- turn_attachments(turn)}
                    class="rounded-full border border-white/10 px-3 py-1 font-mono uppercase tracking-[0.18em] text-[var(--hx-mute)]"
                  >
                    {attachment_label(attachment)}
                  </span>
                </div>
              </div>

              <div
                :if={@streaming_content}
                class="max-w-[85%] rounded-[1.6rem] border border-cyan-400/20 bg-cyan-400/10 px-5 py-4 text-sm leading-7 text-cyan-100"
              >
                <div class="font-mono text-[10px] uppercase tracking-[0.18em] text-cyan-200">
                  assistant · streaming
                </div>
                <div class="mt-2 whitespace-pre-wrap">{@streaming_content}</div>
              </div>
            </div>

            <div class="border-t border-white/10 px-6 py-5">
              <.form for={@message_form} phx-submit="send_message" class="grid gap-3">
                <.input
                  field={@message_form[:message]}
                  type="textarea"
                  label="Message"
                  placeholder={
                    @config.composer_placeholder || "Ask Hydra-X anything about this workspace..."
                  }
                />
                <div :if={attachments_enabled?(@config)} class="grid gap-2">
                  <label class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                    Attachments
                  </label>
                  <.live_file_input
                    upload={@uploads.attachments}
                    class="block w-full text-sm text-[var(--hx-mute)]"
                  />
                  <div class="flex flex-wrap gap-2 text-xs text-[var(--hx-mute)]">
                    <span
                      :for={entry <- @uploads.attachments.entries}
                      class="rounded-full border border-white/10 px-3 py-1 font-mono uppercase tracking-[0.18em]"
                    >
                      {entry.client_name} · {entry.client_size} bytes
                    </span>
                  </div>
                </div>
                <div class="flex items-center justify-between gap-3">
                  <div class="text-xs text-[var(--hx-mute)]">
                    Session-backed thread with persisted runtime history and upload metadata.
                  </div>
                  <.button disabled={!@config.enabled}>Send</.button>
                </div>
              </.form>
            </div>
          </article>
        </section>
      </div>
    </div>
    """
  end

  defp webchat_conversation(%{default_agent_id: nil}, _session_ref), do: nil

  defp webchat_conversation(config, session_ref) do
    case Runtime.find_conversation(config.default_agent_id, "webchat", session_ref) do
      nil -> nil
      conversation -> Runtime.get_conversation!(conversation.id)
    end
  end

  defp webchat_session_ref(session) do
    base =
      session["webchat_session_id"] || "webchat-anonymous"

    "webchat:" <> String.slice(Base.encode16(:crypto.hash(:sha256, base), case: :lower), 0, 20)
  end

  defp conversation_state(_conversation, streaming_content, _session_state)
       when is_binary(streaming_content) and streaming_content != "",
       do: "assistant streaming"

  defp conversation_state(_conversation, _streaming_content, %{reset_reason: "idle_timeout"}),
    do: "session rotated after idle timeout"

  defp conversation_state(_conversation, _streaming_content, %{reset_reason: "max_age"}),
    do: "session rotated after max age"

  defp conversation_state(_conversation, _streaming_content, %{reset_reason: "manual_reset"}),
    do: "session reset"

  defp conversation_state(nil, _streaming_content, _session_state), do: "awaiting first message"

  defp conversation_state(%{status: status}, _streaming_content, _session_state),
    do: "conversation #{status}"

  defp channel_streaming_preview(nil), do: nil

  defp channel_streaming_preview(%{status: "streaming", stream_capture: %{"content" => content}})
       when is_binary(content) and content != "",
       do: content

  defp channel_streaming_preview(%{
         handoff: %{"waiting_for" => "stream_response"},
         stream_capture: %{"content" => content}
       })
       when is_binary(content) and content != "",
       do: content

  defp channel_streaming_preview(_state), do: nil

  defp conversation_turn_count(nil), do: 0
  defp conversation_turn_count(conversation), do: length(conversation.turns || [])

  defp webchat_session_state(session, config) do
    %{
      display_name: blank_to_nil(session["webchat_display_name"]),
      created_at: integer_session_value(session["webchat_session_created_at"]),
      last_active_at: integer_session_value(session["webchat_session_last_active_at"]),
      reset_reason: blank_to_nil(session["webchat_session_reset_reason"]),
      allow_anonymous_messages: config.allow_anonymous_messages
    }
  end

  defp maybe_flash_reset_reason(socket, nil), do: socket

  defp maybe_flash_reset_reason(socket, "idle_timeout"),
    do:
      put_flash(socket, :info, "Webchat session expired after the idle timeout and was rotated.")

  defp maybe_flash_reset_reason(socket, "max_age"),
    do:
      put_flash(
        socket,
        :info,
        "Webchat session expired after the maximum session age and was rotated."
      )

  defp maybe_flash_reset_reason(socket, "manual_reset"),
    do: put_flash(socket, :info, "Webchat session reset.")

  defp maybe_flash_reset_reason(socket, _reason), do: socket

  defp configure_attachments(socket, config) do
    if attachments_enabled?(config) do
      allow_upload(socket, :attachments,
        accept: ~w(.txt .md .csv .json .png .jpg .jpeg .gif .webp .pdf),
        max_entries: config.max_attachment_count,
        max_file_size: config.max_attachment_size_kb * 1_024,
        auto_upload: false
      )
    else
      socket
    end
  end

  defp consume_webchat_attachments(socket) do
    if attachments_enabled?(socket.assigns.config) do
      consume_uploaded_entries(socket, :attachments, fn _meta, entry ->
        {:ok,
         %{
           "kind" => "upload",
           "id" => entry.ref,
           "file_name" => entry.client_name,
           "content_type" => entry.client_type,
           "size" => entry.client_size,
           "upload_ref" => entry.ref
         }}
      end)
    else
      []
    end
  end

  defp pending_attachment_count(socket) do
    if attachments_enabled?(socket.assigns.config) do
      length(socket.assigns.uploads.attachments.entries)
    else
      0
    end
  end

  defp identity_required?(session_state) do
    not session_state.allow_anonymous_messages and is_nil(session_state.display_name)
  end

  defp identity_policy_label(%{allow_anonymous_messages: true, display_name: nil}),
    do: "anonymous allowed"

  defp identity_policy_label(%{allow_anonymous_messages: true, display_name: display_name}),
    do: "named session #{display_name}"

  defp identity_policy_label(%{allow_anonymous_messages: false, display_name: nil}),
    do: "display name required"

  defp identity_policy_label(%{allow_anonymous_messages: false, display_name: display_name}),
    do: "identity locked to #{display_name}"

  defp attachment_policy_label(config) do
    if attachments_enabled?(config) do
      "enabled · #{config.max_attachment_count} files · #{config.max_attachment_size_kb} KB each"
    else
      "disabled"
    end
  end

  defp attachments_enabled?(config), do: config.attachments_enabled == true

  defp turn_role_label(%{role: "user"} = turn) do
    metadata = turn.metadata || %{}

    display_name =
      metadata["display_name"] || metadata[:display_name]

    if is_binary(display_name) and display_name != "", do: "user · #{display_name}", else: "user"
  end

  defp turn_role_label(%{role: role}), do: role

  defp turn_attachments(turn) do
    metadata = turn.metadata || %{}
    metadata["attachments"] || metadata[:attachments] || []
  end

  defp attachment_label(attachment) do
    kind = attachment["kind"] || attachment[:kind] || "attachment"
    file_name = attachment["file_name"] || attachment[:file_name]
    content_type = attachment["content_type"] || attachment[:content_type]

    [kind, file_name, content_type]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" · ")
  end

  defp integer_session_value(value) when is_integer(value), do: value

  defp integer_session_value(value) when is_binary(value) do
    String.to_integer(value)
  rescue
    ArgumentError -> nil
  end

  defp integer_session_value(_value), do: nil

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
