defmodule HydraXWeb.ConversationsLive do
  use HydraXWeb, :live_view

  alias HydraX.Gateway
  alias HydraX.Runtime
  alias HydraXWeb.AppShell

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(HydraX.PubSub, "conversations")
      Phoenix.PubSub.subscribe(HydraX.PubSub, "conversations:stream")
    end
    filters = default_filters()
    {conversations, has_next} = list_conversations_paginated(filters, 1)
    selected = conversations |> List.first() |> maybe_load()
    agents = Runtime.list_agents()

    {:ok,
     socket
     |> assign(:page_title, "Conversations")
     |> assign(:current, "conversations")
     |> assign(:stats, stats())
     |> assign(:agents, agents)
     |> assign(:filters, filters)
     |> assign(:page, 1)
     |> assign(:has_next, has_next)
     |> assign(:filter_form, to_form(filters, as: :filters))
     |> assign(:conversations, conversations)
     |> assign(:selected, selected)
     |> assign(:compaction, selected && Runtime.conversation_compaction(selected.id))
     |> assign(:new_form, to_form(default_new_conversation(agents), as: :conversation))
     |> assign(:reply_form, to_form(%{"message" => ""}, as: :reply))
     |> assign(:rename_form, rename_form(selected))
     |> assign(:streaming_content, nil)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    selected =
      case params["conversation_id"] do
        nil -> socket.assigns.selected
        id -> Runtime.get_conversation!(id)
      end

    {:noreply,
     socket
     |> assign(:selected, selected)
     |> assign(:compaction, selected && Runtime.conversation_compaction(selected.id))}
  end

  @impl true
  def handle_event("rename_conversation", %{"rename" => %{"title" => title}}, socket) do
    conversation = socket.assigns.selected

    case Runtime.save_conversation(conversation, %{title: title}) do
      {:ok, updated} ->
        selected = Runtime.get_conversation!(updated.id)

        {:noreply,
         socket
         |> put_flash(:info, "Conversation renamed")
         |> assign(:conversations, list_conversations(socket.assigns.filters))
         |> assign(:selected, selected)
         |> assign(:compaction, Runtime.conversation_compaction(selected.id))
         |> assign(:rename_form, rename_form(selected))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Rename failed: #{format_reason(reason)}")}
    end
  end

  def handle_event("archive_conversation", %{"id" => id}, socket) do
    updated = Runtime.archive_conversation!(id)
    conversations = list_conversations(socket.assigns.filters)
    selected = maybe_refresh_selection(conversations, updated.id)

    {:noreply,
     socket
     |> put_flash(:info, "Conversation archived")
     |> assign(:conversations, conversations)
     |> assign(:selected, selected)
     |> assign(:compaction, selected && Runtime.conversation_compaction(selected.id))
     |> assign(:rename_form, rename_form(selected))
     |> assign(:stats, stats())}
  end

  def handle_event("export_conversation", %{"id" => id}, socket) do
    export = Runtime.export_conversation_transcript!(id)

    {:noreply,
     socket
     |> put_flash(:info, "Transcript exported to #{export.path}")}
  end

  def handle_event("start_conversation", %{"conversation" => params}, socket) do
    with {:ok, agent} <- fetch_agent(params["agent_id"]),
         {:ok, _pid} <- HydraX.Agent.ensure_started(agent),
         {:ok, conversation} <-
           Runtime.start_conversation(agent, %{
             channel: blank_to_default(params["channel"], "control_plane"),
             title: blank_to_default(params["title"], "Control plane · #{Date.utc_today()}"),
             metadata: %{"source" => "control_plane"}
           }),
         {:ok, selected} <-
           submit_reply(agent, conversation, params["message"], %{"source" => "control_plane"}) do
      conversations = list_conversations(socket.assigns.filters)

      {:noreply,
       socket
       |> put_flash(:info, "Conversation started")
       |> assign(:conversations, conversations)
       |> assign(:selected, selected)
       |> assign(:compaction, Runtime.conversation_compaction(selected.id))
       |> assign(:stats, stats())
       |> assign(:rename_form, rename_form(selected))
       |> assign(:reply_form, to_form(%{"message" => ""}, as: :reply))}
    else
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Start failed: #{format_reason(reason)}")}
    end
  end

  def handle_event("send_reply", %{"reply" => %{"message" => message}}, socket) do
    conversation = socket.assigns.selected
    agent = conversation.agent || Runtime.get_agent!(conversation.agent_id)

    case submit_reply(agent, conversation, message, %{"source" => "control_plane"}) do
      {:ok, selected} ->
        {:noreply,
         socket
         |> put_flash(:info, "Reply sent")
         |> assign(:conversations, list_conversations(socket.assigns.filters))
         |> assign(:selected, selected)
         |> assign(:compaction, Runtime.conversation_compaction(selected.id))
         |> assign(:stats, stats())
         |> assign(:rename_form, rename_form(selected))
         |> assign(:reply_form, to_form(%{"message" => ""}, as: :reply))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Reply failed: #{format_reason(reason)}")}
    end
  end

  def handle_event("retry_delivery", %{"id" => id}, socket) do
    conversation = Runtime.get_conversation!(id)

    case Gateway.retry_conversation_delivery(conversation) do
      {:ok, _updated} ->
        refreshed = Runtime.get_conversation!(conversation.id)

        {:noreply,
         socket
         |> put_flash(:info, "Telegram delivery retried")
         |> assign(:conversations, list_conversations(socket.assigns.filters))
         |> assign(:selected, refreshed)
         |> assign(:compaction, Runtime.conversation_compaction(refreshed.id))
         |> assign(:rename_form, rename_form(refreshed))
         |> assign(:stats, stats())}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Retry failed: #{inspect(reason)}")}
    end
  end

  def handle_event("filter_conversations", %{"filters" => params}, socket) do
    filters =
      default_filters()
      |> Map.merge(params)

    {conversations, has_next} = list_conversations_paginated(filters, 1)

    selected =
      maybe_refresh_selection(
        conversations,
        socket.assigns.selected && socket.assigns.selected.id
      )

    selected = selected || conversations |> List.first() |> maybe_load()

    {:noreply,
     socket
     |> assign(:filters, filters)
     |> assign(:page, 1)
     |> assign(:has_next, has_next)
     |> assign(:filter_form, to_form(filters, as: :filters))
     |> assign(:conversations, conversations)
     |> assign(:selected, selected)
     |> assign(:compaction, selected && Runtime.conversation_compaction(selected.id))
     |> assign(:rename_form, rename_form(selected))}
  end

  def handle_event("paginate", %{"page" => page}, socket) do
    page = safe_page_number(page)
    {conversations, has_next} = list_conversations_paginated(socket.assigns.filters, page)

    selected =
      maybe_refresh_selection(
        conversations,
        socket.assigns.selected && socket.assigns.selected.id
      )

    selected = selected || conversations |> List.first() |> maybe_load()

    {:noreply,
     socket
     |> assign(:page, page)
     |> assign(:has_next, has_next)
     |> assign(:conversations, conversations)
     |> assign(:selected, selected)
     |> assign(:compaction, selected && Runtime.conversation_compaction(selected.id))
     |> assign(:rename_form, rename_form(selected))}
  end

  def handle_event("review_compaction", %{"id" => id}, socket) do
    compaction = Runtime.review_conversation_compaction!(String.to_integer(id))
    selected = Runtime.get_conversation!(compaction.conversation.id)

    {:noreply,
     socket
     |> put_flash(:info, "Conversation compaction reviewed")
     |> assign(:selected, selected)
     |> assign(:compaction, compaction)
     |> assign(:conversations, list_conversations(socket.assigns.filters))
     |> assign(:rename_form, rename_form(selected))
     |> assign(:stats, stats())}
  end

  def handle_event("reset_compaction", %{"id" => id}, socket) do
    compaction = Runtime.reset_conversation_compaction!(String.to_integer(id))
    selected = Runtime.get_conversation!(compaction.conversation.id)

    {:noreply,
     socket
     |> put_flash(:info, "Conversation summary reset")
     |> assign(:selected, selected)
     |> assign(:compaction, compaction)
     |> assign(:conversations, list_conversations(socket.assigns.filters))
     |> assign(:rename_form, rename_form(selected))
     |> assign(:stats, stats())}
  end

  def handle_info({:stream_chunk, conversation_id, delta}, socket) do
    if socket.assigns.selected && socket.assigns.selected.id == conversation_id do
      current = socket.assigns.streaming_content || ""
      {:noreply, assign(socket, :streaming_content, current <> delta)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:stream_done, conversation_id}, socket) do
    if socket.assigns.selected && socket.assigns.selected.id == conversation_id do
      {:noreply, assign(socket, :streaming_content, nil)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:conversation_updated, _conversation_id}, socket) do
    conversations = list_conversations(socket.assigns.filters)

    selected =
      if socket.assigns.selected do
        Runtime.get_conversation!(socket.assigns.selected.id)
      end

    {:noreply,
     socket
     |> assign(:conversations, conversations)
     |> assign(:selected, selected)
     |> assign(:compaction, selected && Runtime.conversation_compaction(selected.id))
     |> assign(:streaming_content, nil)
     |> assign(:stats, stats())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <AppShell.shell current={@current} stats={@stats} flash={@flash}>
      <section class="grid gap-6 xl:grid-cols-[0.8fr_1.2fr]">
        <article class="glass-panel p-6">
          <div class="text-xs uppercase tracking-[0.28em] text-[var(--hx-mute)]">Conversations</div>
          <.form for={@filter_form} phx-submit="filter_conversations" class="mt-4 space-y-2">
            <.input field={@filter_form[:search]} label="Search" />
            <.input
              field={@filter_form[:status]}
              type="select"
              label="Status"
              options={[{"All statuses", ""}, {"Active", "active"}, {"Archived", "archived"}]}
            />
            <.input
              field={@filter_form[:channel]}
              type="select"
              label="Channel"
              options={[
                {"All channels", ""},
                {"Control plane", "control_plane"},
                {"CLI", "cli"},
                {"Telegram", "telegram"}
              ]}
            />
            <div class="pt-1">
              <.button>Filter conversations</.button>
            </div>
          </.form>
          <.form for={@new_form} phx-submit="start_conversation" class="mt-4 space-y-2">
            <.input
              field={@new_form[:agent_id]}
              type="select"
              label="Agent"
              options={Enum.map(@agents, &{"#{&1.name} (#{&1.slug})", &1.id})}
            />
            <.input
              field={@new_form[:channel]}
              type="select"
              label="Channel"
              options={[{"Control plane", "control_plane"}, {"CLI", "cli"}]}
            />
            <.input field={@new_form[:title]} label="Title" />
            <.input field={@new_form[:message]} type="textarea" label="Initial message" />
            <div class="pt-1">
              <.button>Start conversation</.button>
            </div>
          </.form>
          <div class="mt-4 space-y-3">
            <.link
              :for={conversation <- @conversations}
              patch={~p"/conversations?#{[conversation_id: conversation.id]}"}
              class={[
                "block rounded-2xl border px-4 py-4 transition",
                if(@selected && @selected.id == conversation.id,
                  do: "border-[var(--hx-accent)] bg-[rgba(245,110,66,0.08)]",
                  else: "border-white/10 bg-black/10 hover:bg-white/5"
                )
              ]}
            >
              <div class="flex items-start justify-between gap-4">
                <div>
                  <div class="font-display text-2xl">{conversation.title || "Untitled"}</div>
                  <div class="mt-1 text-sm text-[var(--hx-mute)]">
                    {conversation.channel} · {conversation.agent.name}
                  </div>
                </div>
                <span
                  :if={delivery = last_delivery(conversation)}
                  class={[
                    "rounded-full border px-3 py-1 font-mono text-[10px] uppercase tracking-[0.18em]",
                    delivery_badge_class(delivery["status"])
                  ]}
                >
                  {delivery["status"]}
                </span>
              </div>
            </.link>
          </div>
          <.pagination page={@page} has_next={@has_next} />
        </article>

        <article class="glass-panel p-6">
          <div :if={@selected} class="space-y-4">
            <div class="border-b border-white/10 pb-4">
              <div class="text-xs uppercase tracking-[0.28em] text-[var(--hx-mute)]">Transcript</div>
              <h2 class="mt-3 font-display text-4xl">{@selected.title || "Untitled conversation"}</h2>
              <div :if={delivery = last_delivery(@selected)} class="mt-4 flex flex-wrap gap-2 text-xs">
                <span class={[
                  "rounded-full border px-3 py-1 font-mono uppercase tracking-[0.18em]",
                  delivery_badge_class(delivery["status"])
                ]}>
                  delivery {delivery["status"]}
                </span>
                <span class="rounded-full border border-white/10 px-3 py-1 font-mono uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                  chat {delivery["external_ref"]}
                </span>
                <span
                  :if={delivery["provider_message_id"]}
                  class="rounded-full border border-white/10 px-3 py-1 font-mono uppercase tracking-[0.18em] text-[var(--hx-mute)]"
                >
                  message {delivery["provider_message_id"]}
                </span>
              </div>
              <p :if={delivery_reason(@selected)} class="mt-3 text-sm text-[var(--hx-mute)]">
                {delivery_reason(@selected)}
              </p>
              <div :if={retryable_delivery?(@selected)} class="mt-4">
                <button
                  type="button"
                  phx-click="retry_delivery"
                  phx-value-id={@selected.id}
                  class="btn btn-outline border-white/10 bg-white/5 text-white hover:bg-white/10"
                >
                  Retry Telegram delivery
                </button>
              </div>
              <div class="mt-4 flex flex-wrap gap-3">
                <button
                  type="button"
                  phx-click="archive_conversation"
                  phx-value-id={@selected.id}
                  class="btn btn-outline border-white/10 bg-white/5 text-white hover:bg-white/10"
                >
                  Archive
                </button>
                <button
                  type="button"
                  phx-click="export_conversation"
                  phx-value-id={@selected.id}
                  class="btn btn-outline border-white/10 bg-white/5 text-white hover:bg-white/10"
                >
                  Export transcript
                </button>
              </div>
              <div class="mt-4 rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
                <div class="flex flex-wrap items-center justify-between gap-3">
                  <div>
                    <div class="font-mono text-[10px] uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                      Compaction
                    </div>
                    <div class="mt-2 text-sm text-[var(--hx-mute)]">
                      {compaction_label(@compaction)}
                    </div>
                  </div>
                  <div class="flex flex-wrap gap-2">
                    <button
                      type="button"
                      phx-click="review_compaction"
                      phx-value-id={@selected.id}
                      class="btn btn-outline border-white/10 bg-white/5 text-white hover:bg-white/10"
                    >
                      Review compaction
                    </button>
                    <button
                      type="button"
                      phx-click="reset_compaction"
                      phx-value-id={@selected.id}
                      class="btn btn-outline border-white/10 bg-white/5 text-white hover:bg-white/10"
                    >
                      Reset summary
                    </button>
                  </div>
                </div>
                <p class="mt-3 whitespace-pre-wrap text-sm text-[var(--hx-mute)]">
                  {(@compaction && @compaction.summary) || "No summary checkpoint yet"}
                </p>
                <div :if={@compaction} class="mt-2 text-xs text-[var(--hx-mute)]">
                  Policy thresholds: {compaction_thresholds_label(@compaction.thresholds)}
                </div>
              </div>
              <.form for={@rename_form} phx-submit="rename_conversation" class="mt-4 space-y-2">
                <.input field={@rename_form[:title]} label="Title" />
                <div class="pt-1">
                  <.button>Rename conversation</.button>
                </div>
              </.form>
              <.form for={@reply_form} phx-submit="send_reply" class="mt-4 space-y-2">
                <.input field={@reply_form[:message]} type="textarea" label="Reply" />
                <div class="pt-1">
                  <.button>Send reply</.button>
                </div>
              </.form>
            </div>

            <div class="space-y-3">
              <div :for={turn <- @selected.turns} class="rounded-2xl border border-white/10 px-4 py-4">
                <div class="flex items-center justify-between gap-4">
                  <span class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-accent)]">
                    {turn.role}
                  </span>
                  <span class="text-xs text-[var(--hx-mute)]">#{turn.sequence}</span>
                </div>
                <p class="mt-3 whitespace-pre-wrap text-sm leading-6">{turn.content}</p>
                <div :if={turn_attachments(turn) != []} class="mt-3 flex flex-wrap gap-2 text-xs">
                  <span
                    :for={attachment <- turn_attachments(turn)}
                    class="rounded-full border border-white/10 px-3 py-1 font-mono uppercase tracking-[0.18em] text-[var(--hx-mute)]"
                  >
                    {attachment_label(attachment)}
                  </span>
                </div>
              </div>

              <div :if={@streaming_content} class="rounded-2xl border border-[var(--hx-accent)]/30 bg-[rgba(245,110,66,0.04)] px-4 py-4">
                <div class="flex items-center gap-2">
                  <span class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-accent)]">
                    assistant
                  </span>
                  <span class="inline-flex items-center gap-1 text-xs text-[var(--hx-accent)]">
                    <span class="animate-pulse">●</span> streaming
                  </span>
                </div>
                <p class="mt-3 whitespace-pre-wrap text-sm leading-6">{@streaming_content}</p>
              </div>
            </div>
          </div>

          <div
            :if={is_nil(@selected)}
            class="rounded-2xl border border-dashed border-white/10 px-4 py-8 text-center text-[var(--hx-mute)]"
          >
            No conversation selected.
          </div>
        </article>
      </section>
    </AppShell.shell>
    """
  end

  defp maybe_load(nil), do: nil
  defp maybe_load(conversation), do: Runtime.get_conversation!(conversation.id)

  defp maybe_refresh_selection(conversations, id) do
    case Enum.find(conversations, &(&1.id == id)) do
      nil -> nil
      conversation -> Runtime.get_conversation!(conversation.id)
    end
  end

  defp last_delivery(conversation) do
    metadata = conversation.metadata || %{}
    metadata["last_delivery"] || metadata[:last_delivery]
  end

  defp delivery_reason(conversation) do
    case last_delivery(conversation) do
      nil -> nil
      delivery -> delivery["reason"] || delivery[:reason]
    end
  end

  defp delivery_badge_class("delivered"),
    do: "border-emerald-400/30 bg-emerald-400/10 text-emerald-200"

  defp delivery_badge_class("failed"), do: "border-rose-400/30 bg-rose-400/10 text-rose-200"
  defp delivery_badge_class(_), do: "border-white/10 bg-black/10 text-[var(--hx-mute)]"

  defp retryable_delivery?(conversation) do
    case last_delivery(conversation) do
      %{"status" => "failed", "channel" => "telegram"} -> true
      %{status: "failed", channel: "telegram"} -> true
      _ -> false
    end
  end

  defp turn_attachments(turn) do
    metadata = turn.metadata || %{}
    metadata["attachments"] || metadata[:attachments] || []
  end

  defp attachment_label(attachment) do
    kind = attachment["kind"] || attachment[:kind] || "attachment"
    file_name = attachment["file_name"] || attachment[:file_name]

    if is_binary(file_name) and file_name != "" do
      "#{kind}: #{file_name}"
    else
      kind
    end
  end

  defp fetch_agent(nil), do: {:error, :missing_agent}
  defp fetch_agent(""), do: {:error, :missing_agent}

  defp fetch_agent(id) do
    {:ok, Runtime.get_agent!(id)}
  rescue
    Ecto.NoResultsError -> {:error, :agent_not_found}
  end

  defp submit_reply(_agent, _conversation, message, _metadata) when message in [nil, ""] do
    {:error, :empty_message}
  end

  defp submit_reply(agent, conversation, message, metadata) do
    _response = HydraX.Agent.Channel.submit(agent, conversation, message, metadata)
    {:ok, Runtime.get_conversation!(conversation.id)}
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp default_new_conversation(agents) do
    %{
      "agent_id" => agents |> List.first() |> then(&(&1 && to_string(&1.id))) || "",
      "channel" => "control_plane",
      "title" => "Control plane · #{Date.utc_today()}",
      "message" => ""
    }
  end

  defp default_filters do
    %{"search" => "", "status" => "", "channel" => ""}
  end

  @page_size 25

  defp list_conversations(filters) do
    Runtime.list_conversations(
      limit: @page_size,
      search: blank_to_nil(filters["search"]),
      status: blank_to_nil(filters["status"]),
      channel: blank_to_nil(filters["channel"])
    )
  end

  defp list_conversations_paginated(filters, page) do
    results =
      Runtime.list_conversations(
        limit: @page_size + 1,
        offset: (page - 1) * @page_size,
        search: blank_to_nil(filters["search"]),
        status: blank_to_nil(filters["status"]),
        channel: blank_to_nil(filters["channel"])
      )

    {Enum.take(results, @page_size), length(results) > @page_size}
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp rename_form(nil), do: to_form(%{"title" => ""}, as: :rename)
  defp rename_form(conversation), do: to_form(%{"title" => conversation.title || ""}, as: :rename)

  defp blank_to_default(nil, default), do: default
  defp blank_to_default("", default), do: default
  defp blank_to_default(value, _default), do: value

  defp compaction_label(nil), do: "No compaction data available"

  defp compaction_label(compaction) do
    level = compaction.level || "idle"
    "#{compaction.turn_count} turns · #{level}"
  end

  defp compaction_thresholds_label(%{soft: soft, medium: medium, hard: hard}) do
    "soft #{soft} · medium #{medium} · hard #{hard}"
  end

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)

  defp safe_page_number(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n > 0 -> n
      _ -> 1
    end
  end

  defp safe_page_number(value) when is_integer(value) and value > 0, do: value
  defp safe_page_number(_), do: 1

  defp stats do
    %{
      agents: Runtime.list_agents() |> length(),
      providers: Runtime.list_provider_configs() |> length(),
      turns:
        Runtime.list_conversations(limit: 200)
        |> Enum.flat_map(&Runtime.list_turns(&1.id))
        |> length(),
      memories: HydraX.Memory.list_memories(limit: 1_000) |> length()
    }
  end
end
