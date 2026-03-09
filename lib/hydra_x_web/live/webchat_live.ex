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
    conversation = webchat_conversation(config, session_ref)

    {:ok,
     socket
     |> assign(:page_title, config.title || "Hydra-X Webchat")
     |> assign(:config, config)
     |> assign(:session_ref, session_ref)
     |> assign(:conversation, conversation)
     |> assign(:streaming_content, nil)
     |> assign(:message_form, to_form(%{"message" => ""}, as: :message))}
  end

  @impl true
  def handle_event("send_message", %{"message" => %{"message" => message}}, socket) do
    config = socket.assigns.config
    message = String.trim(message || "")

    cond do
      not config.enabled ->
        {:noreply, put_flash(socket, :error, "Webchat is not enabled on this node.")}

      message == "" ->
        {:noreply, put_flash(socket, :error, "Enter a message first.")}

      true ->
        case Gateway.dispatch_webchat_message(%{
               "session_id" => socket.assigns.session_ref,
               "content" => message,
               "title" => config.title
             }) do
          :ok ->
            conversation = webchat_conversation(config, socket.assigns.session_ref)

            {:noreply,
             socket
             |> assign(:conversation, conversation)
             |> assign(:message_form, to_form(%{"message" => ""}, as: :message))}

          {:error, :webchat_not_configured} ->
            {:noreply, put_flash(socket, :error, "Webchat is not enabled on this node.")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Webchat failed: #{inspect(reason)}")}
        end
    end
  end

  @impl true
  def handle_info({:conversation_updated, conversation_id}, socket) do
    case socket.assigns.conversation do
      %{id: ^conversation_id} ->
        {:noreply, assign(socket, :conversation, Runtime.get_conversation!(conversation_id))}

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
            </div>
            <div
              :if={@config.welcome_prompt not in [nil, ""]}
              class="mt-8 rounded-3xl border border-white/10 bg-[rgba(255,255,255,0.04)] px-5 py-5 text-sm leading-7 text-[var(--hx-mute)]"
            >
              {@config.welcome_prompt}
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
                  {turn.role}
                </div>
                <div class="mt-2 whitespace-pre-wrap">{turn.content}</div>
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
                <div class="flex items-center justify-between gap-3">
                  <div class="text-xs text-[var(--hx-mute)]">
                    Session-backed thread with persisted runtime history.
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
      session["webchat_session_id"] ||
        session["_csrf_token"] ||
        session["live_socket_id"] ||
        "webchat-anonymous"

    "webchat:" <> String.slice(Base.encode16(:crypto.hash(:sha256, base), case: :lower), 0, 20)
  end
end
