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
    channel_state = selected && Runtime.conversation_channel_state(selected.id)

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
     |> assign(:channel_state, channel_state)
     |> assign(:new_form, to_form(default_new_conversation(agents), as: :conversation))
     |> assign(:reply_form, to_form(%{"message" => ""}, as: :reply))
     |> assign(:rename_form, rename_form(selected))
     |> assign(:streaming_content, channel_streaming_preview(channel_state))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    selected =
      case params["conversation_id"] do
        nil -> socket.assigns.selected
        id -> Runtime.get_conversation!(id)
      end

    channel_state = selected && Runtime.conversation_channel_state(selected.id)

    {:noreply,
     socket
     |> assign(:selected, selected)
     |> assign(:compaction, selected && Runtime.conversation_compaction(selected.id))
     |> assign(:channel_state, channel_state)
     |> assign(:streaming_content, channel_streaming_preview(channel_state))}
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
         |> assign(:channel_state, Runtime.conversation_channel_state(selected.id))
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
     |> assign(:channel_state, selected && Runtime.conversation_channel_state(selected.id))
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
         {:ok, selected, flash_message} <-
           submit_reply(
             agent,
             conversation,
             params["message"],
             %{"source" => "control_plane"},
             :start
           ) do
      conversations = list_conversations(socket.assigns.filters)

      {:noreply,
       socket
       |> put_flash(:info, flash_message)
       |> assign(:conversations, conversations)
       |> assign(:selected, selected)
       |> assign(:compaction, Runtime.conversation_compaction(selected.id))
       |> assign(:channel_state, Runtime.conversation_channel_state(selected.id))
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

    case submit_reply(agent, conversation, message, %{"source" => "control_plane"}, :reply) do
      {:ok, selected, flash_message} ->
        {:noreply,
         socket
         |> put_flash(:info, flash_message)
         |> assign(:conversations, list_conversations(socket.assigns.filters))
         |> assign(:selected, selected)
         |> assign(:compaction, Runtime.conversation_compaction(selected.id))
         |> assign(:channel_state, Runtime.conversation_channel_state(selected.id))
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
        channel = retry_delivery_channel(refreshed)

        {:noreply,
         socket
         |> put_flash(:info, "#{String.capitalize(channel)} delivery retried")
         |> assign(:conversations, list_conversations(socket.assigns.filters))
         |> assign(:selected, refreshed)
         |> assign(:compaction, Runtime.conversation_compaction(refreshed.id))
         |> assign(:channel_state, Runtime.conversation_channel_state(refreshed.id))
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
     |> assign(:channel_state, selected && Runtime.conversation_channel_state(selected.id))
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
     |> assign(:channel_state, selected && Runtime.conversation_channel_state(selected.id))
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
     |> assign(:channel_state, Runtime.conversation_channel_state(selected.id))
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
     |> assign(:channel_state, Runtime.conversation_channel_state(selected.id))
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

    channel_state = selected && Runtime.conversation_channel_state(selected.id)

    {:noreply,
     socket
     |> assign(:conversations, conversations)
     |> assign(:selected, selected)
     |> assign(:compaction, selected && Runtime.conversation_compaction(selected.id))
     |> assign(:channel_state, channel_state)
     |> assign(:streaming_content, channel_streaming_preview(channel_state))
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
                <span
                  :for={label <- delivery_meta_labels(delivery)}
                  class="rounded-full border border-white/10 px-3 py-1 font-mono uppercase tracking-[0.18em] text-[var(--hx-mute)]"
                >
                  {label}
                </span>
                <span
                  :for={label <- delivery_context_labels(delivery)}
                  class="rounded-full border border-white/10 px-3 py-1 font-mono uppercase tracking-[0.18em] text-[var(--hx-mute)]"
                >
                  {label}
                </span>
              </div>
              <p :if={delivery_reason(@selected)} class="mt-3 text-sm text-[var(--hx-mute)]">
                {delivery_reason(@selected)}
              </p>
              <div
                :if={delivery_attempt_history(@selected) != []}
                class="mt-3 rounded-2xl border border-white/10 bg-black/10 px-4 py-4"
              >
                <div class="font-mono text-[10px] uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                  Delivery diagnostics
                </div>
                <div class="mt-3 space-y-2 text-xs text-[var(--hx-mute)]">
                  <div :for={entry <- delivery_attempt_history(@selected)}>
                    {format_delivery_attempt(entry)}
                  </div>
                </div>
              </div>
              <div
                :if={formatted_delivery_payload(@selected)}
                class="mt-3 rounded-2xl border border-white/10 bg-black/10 px-4 py-4"
              >
                <div class="font-mono text-[10px] uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                  Native payload preview
                </div>
                <pre class="mt-3 overflow-x-auto whitespace-pre-wrap text-xs leading-6 text-[var(--hx-mute)]">{formatted_delivery_payload(@selected)}</pre>
              </div>
              <div :if={retryable_delivery?(@selected)} class="mt-4">
                <button
                  type="button"
                  phx-click="retry_delivery"
                  phx-value-id={@selected.id}
                  class="btn btn-outline border-white/10 bg-white/5 text-white hover:bg-white/10"
                >
                  Retry {String.capitalize(retry_delivery_channel(@selected))} delivery
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
              <div class="mt-4 rounded-2xl border border-white/10 bg-black/10 px-4 py-4">
                <div class="font-mono text-[10px] uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                  Execution plan
                </div>
                <div class="mt-3 flex flex-wrap gap-2 text-xs">
                  <span class="rounded-full border border-white/10 px-3 py-1 font-mono uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                    status {(@channel_state && @channel_state.status) || "idle"}
                  </span>
                  <span
                    :if={@channel_state && @channel_state.resumable}
                    class="rounded-full border border-amber-400/20 bg-amber-400/10 px-3 py-1 font-mono uppercase tracking-[0.18em] text-amber-200"
                  >
                    resumable
                  </span>
                  <span
                    :if={@channel_state && @channel_state.resume_stage}
                    class="rounded-full border border-cyan-400/20 bg-cyan-400/10 px-3 py-1 font-mono uppercase tracking-[0.18em] text-cyan-200"
                  >
                    replay {@channel_state.resume_stage}
                  </span>
                  <span
                    :if={@channel_state && @channel_state.provider}
                    class="rounded-full border border-white/10 px-3 py-1 font-mono uppercase tracking-[0.18em] text-[var(--hx-mute)]"
                  >
                    provider {@channel_state.provider}
                  </span>
                  <span class="rounded-full border border-white/10 px-3 py-1 font-mono uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                    tool rounds {(@channel_state && @channel_state.tool_rounds) || 0}
                  </span>
                </div>
                <p class="mt-3 text-sm text-[var(--hx-mute)]">
                  {channel_plan_summary(@channel_state)}
                </p>
                <p
                  :if={channel_recovery_summary(@channel_state)}
                  class="mt-2 text-xs text-[var(--hx-mute)]"
                >
                  {channel_recovery_summary(@channel_state)}
                </p>
                <p
                  :if={channel_ownership_summary(@channel_state)}
                  class="mt-2 text-xs text-[var(--hx-mute)]"
                >
                  {channel_ownership_summary(@channel_state)}
                </p>
                <p
                  :if={channel_handoff_summary(@channel_state)}
                  class="mt-2 text-xs text-amber-200"
                >
                  {channel_handoff_summary(@channel_state)}
                </p>
                <p
                  :if={channel_resume_summary(@channel_state)}
                  class="mt-2 text-xs text-cyan-200"
                >
                  {channel_resume_summary(@channel_state)}
                </p>
                <p
                  :if={channel_pending_response_summary(@channel_state)}
                  class="mt-2 text-xs text-[var(--hx-mute)]"
                >
                  {channel_pending_response_summary(@channel_state)}
                </p>
                <div
                  :if={channel_stream_capture(@channel_state)}
                  class="mt-3 rounded-2xl border border-amber-400/20 bg-amber-400/5 px-4 py-4"
                >
                  <div class="font-mono text-[10px] uppercase tracking-[0.18em] text-amber-200">
                    Partial stream capture
                  </div>
                  <div class="mt-3 flex flex-wrap gap-2 text-xs">
                    <span
                      :for={label <- channel_stream_capture_labels(@channel_state)}
                      class="rounded-full border border-amber-400/20 bg-amber-400/10 px-3 py-1 font-mono uppercase tracking-[0.18em] text-amber-200"
                    >
                      {label}
                    </span>
                  </div>
                  <p class="mt-3 whitespace-pre-wrap text-sm leading-6 text-white/80">
                    {stream_capture_preview(channel_stream_capture(@channel_state))}
                  </p>
                </div>
                <div :if={channel_steps(@channel_state) != []} class="mt-3 space-y-2">
                  <div
                    :for={{step, index} <- Enum.with_index(channel_steps(@channel_state))}
                    class="rounded-xl border border-white/10 bg-black/10 px-3 py-3"
                  >
                    <div class="flex items-center justify-between gap-3">
                      <div class="font-mono text-[10px] uppercase tracking-[0.18em] text-[var(--hx-accent)]">
                        {step["kind"]}
                        {if step["name"], do: " · #{step["name"]}", else: ""}
                      </div>
                      <div class={[
                        "rounded-full border px-2 py-1 font-mono text-[10px] uppercase tracking-[0.18em]",
                        step_status_class(
                          step["status"],
                          @channel_state && @channel_state.current_step_index == index
                        )
                      ]}>
                        {step_status_label(
                          step["status"],
                          @channel_state && @channel_state.current_step_index == index
                        )}
                      </div>
                    </div>
                    <p class="mt-2 text-sm text-[var(--hx-mute)]">
                      {step["reason"] || step["label"]}
                    </p>
                    <p :if={step["summary"]} class="mt-2 text-sm text-white/80">
                      {step["summary"]}
                    </p>
                    <p :if={step["output_excerpt"]} class="mt-2 text-sm text-[var(--hx-mute)]">
                      {step["output_excerpt"]}
                    </p>
                    <p
                      :if={step_retry_summary(step)}
                      class="mt-2 text-xs leading-6 text-[var(--hx-mute)]"
                    >
                      {step_retry_summary(step)}
                    </p>
                    <p
                      :if={step_attempt_history_summary(step)}
                      class="mt-2 text-xs leading-6 text-[var(--hx-mute)]"
                    >
                      {step_attempt_history_summary(step)}
                    </p>
                    <div
                      :if={step_detail_labels(step) != []}
                      class="mt-3 flex flex-wrap gap-2 text-xs"
                    >
                      <span
                        :for={label <- step_detail_labels(step)}
                        class="rounded-full border border-white/10 px-2 py-1 font-mono uppercase tracking-[0.18em] text-[var(--hx-mute)]"
                      >
                        {label}
                      </span>
                    </div>
                  </div>
                </div>
                <div :if={channel_skill_hints(@channel_state) != []} class="mt-3 space-y-2">
                  <div class="font-mono text-[10px] uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                    Skill hints
                  </div>
                  <div
                    :for={hint <- channel_skill_hints(@channel_state)}
                    class="rounded-xl border border-white/10 bg-black/10 px-3 py-3"
                  >
                    <div class="flex items-center justify-between gap-3">
                      <div class="text-sm text-[var(--hx-accent)]">{hint["name"]}</div>
                      <div class="text-xs text-[var(--hx-mute)]">{hint["slug"]}</div>
                    </div>
                    <p class="mt-2 text-sm text-[var(--hx-mute)]">{hint["reason"]}</p>
                  </div>
                </div>
                <div :if={channel_tool_results(@channel_state) != []} class="mt-3 space-y-2">
                  <div class="font-mono text-[10px] uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                    Tool execution
                  </div>
                  <div
                    :for={result <- channel_tool_results(@channel_state)}
                    class="rounded-xl border border-white/10 bg-black/10 px-3 py-3"
                  >
                    <div class="flex items-center justify-between gap-3">
                      <div class="text-sm text-[var(--hx-accent)]">{result["tool_name"]}</div>
                      <div class="text-xs text-[var(--hx-mute)]">
                        {if result["is_error"], do: "error", else: "ok"}
                      </div>
                    </div>
                    <p class="mt-2 text-sm text-[var(--hx-mute)]">{result["summary"]}</p>
                  </div>
                </div>
                <div :if={channel_execution_events(@channel_state) != []} class="mt-3 space-y-2">
                  <div class="font-mono text-[10px] uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                    Execution events
                  </div>
                  <div
                    :for={event <- channel_execution_events(@channel_state)}
                    class="rounded-xl border border-white/10 bg-black/10 px-3 py-3"
                  >
                    <div class="flex items-center justify-between gap-3">
                      <div class="text-sm text-[var(--hx-accent)]">{event["phase"]}</div>
                      <div class="text-xs text-[var(--hx-mute)]">
                        {format_event_time(event["at"])}
                      </div>
                    </div>
                    <p class="mt-2 text-sm text-[var(--hx-mute)]">
                      {channel_event_summary(event)}
                    </p>
                    <div
                      :if={event_detail_labels(event) != []}
                      class="mt-3 flex flex-wrap gap-2 text-xs"
                    >
                      <span
                        :for={label <- event_detail_labels(event)}
                        class="rounded-full border border-white/10 px-2 py-1 font-mono uppercase tracking-[0.18em] text-[var(--hx-mute)]"
                      >
                        {label}
                      </span>
                    </div>
                  </div>
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

              <div
                :if={@streaming_content}
                class="rounded-2xl border border-[var(--hx-accent)]/30 bg-[rgba(245,110,66,0.04)] px-4 py-4"
              >
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

  defp delivery_badge_class("streaming"),
    do: "border-amber-400/30 bg-amber-400/10 text-amber-200"

  defp delivery_badge_class("failed"), do: "border-rose-400/30 bg-rose-400/10 text-rose-200"
  defp delivery_badge_class(_), do: "border-white/10 bg-black/10 text-[var(--hx-mute)]"

  defp delivery_context_labels(delivery) when is_map(delivery) do
    reply_context =
      delivery["reply_context"] || delivery[:reply_context] || %{}

    payload =
      delivery["formatted_payload"] || delivery[:formatted_payload] || %{}

    []
    |> maybe_add_delivery_label(
      "reply #{reply_context["reply_to_message_id"] || reply_context[:reply_to_message_id]}"
    )
    |> maybe_add_delivery_label(
      "thread #{reply_context["thread_ts"] || reply_context[:thread_ts]}"
    )
    |> maybe_add_delivery_label(
      "source #{reply_context["source_message_id"] || reply_context[:source_message_id]}"
    )
    |> maybe_add_delivery_label(chunk_count_label(payload))
  end

  defp delivery_context_labels(_), do: []

  defp delivery_meta_labels(delivery) when is_map(delivery) do
    provider_message_ids =
      delivery["provider_message_ids"] || delivery[:provider_message_ids] || []

    metadata =
      delivery["metadata"] || delivery[:metadata] || %{}

    []
    |> maybe_add_delivery_label(
      retry_count_label(delivery["retry_count"] || delivery[:retry_count])
    )
    |> maybe_add_delivery_label(message_ids_label(provider_message_ids))
    |> maybe_add_delivery_label(
      next_retry_label(delivery["next_retry_at"] || delivery[:next_retry_at])
    )
    |> maybe_add_delivery_label(
      dead_letter_label(delivery["dead_lettered_at"] || delivery[:dead_lettered_at])
    )
    |> maybe_add_delivery_label(transport_label(metadata["transport"] || metadata[:transport]))
    |> maybe_add_delivery_label(
      transport_topic_label(metadata["transport_topic"] || metadata[:transport_topic])
    )
  end

  defp delivery_meta_labels(_delivery), do: []

  defp maybe_add_delivery_label(labels, value) when value in ["reply ", "thread ", "source "],
    do: labels

  defp maybe_add_delivery_label(labels, ""), do: labels
  defp maybe_add_delivery_label(labels, value), do: labels ++ [value]

  defp chunk_count_label(payload) when is_map(payload) do
    case payload["chunk_count"] || payload[:chunk_count] do
      count when is_integer(count) and count > 1 -> "chunks #{count}"
      _ -> nil
    end
  end

  defp chunk_count_label(_payload), do: nil

  defp retryable_delivery?(conversation) do
    case last_delivery(conversation) do
      %{"status" => status, "channel" => channel}
      when status in ["failed", "dead_letter"] and
             channel in ["telegram", "discord", "slack", "webchat"] ->
        true

      %{status: status, channel: channel}
      when status in ["failed", "dead_letter"] and
             channel in ["telegram", "discord", "slack", "webchat"] ->
        true

      _ ->
        false
    end
  end

  defp retry_delivery_channel(conversation) do
    case last_delivery(conversation) do
      %{"channel" => channel} when is_binary(channel) -> channel
      %{channel: channel} when is_binary(channel) -> channel
      _ -> "channel"
    end
  end

  defp formatted_delivery_payload(conversation) do
    with delivery when is_map(delivery) <- last_delivery(conversation),
         payload when is_map(payload) <-
           delivery["formatted_payload"] || delivery[:formatted_payload],
         false <- map_size(payload) == 0 do
      Jason.encode!(payload, pretty: true)
    else
      _ -> nil
    end
  end

  defp delivery_attempt_history(conversation) do
    case last_delivery(conversation) do
      %{"attempt_history" => history} when is_list(history) -> Enum.reverse(history)
      %{attempt_history: history} when is_list(history) -> Enum.reverse(history)
      _ -> []
    end
  end

  defp format_delivery_attempt(entry) do
    recorded_at = entry["recorded_at"] || entry[:recorded_at]
    provider_message_ids = entry["provider_message_ids"] || entry[:provider_message_ids] || []

    [
      entry["status"] || entry[:status] || "unknown",
      retry_count_label(entry["retry_count"] || entry[:retry_count]),
      entry["reason"] || entry[:reason],
      if(recorded_at, do: format_delivery_time(recorded_at)),
      message_ids_label(provider_message_ids),
      reply_context_attempt_label(entry["reply_context"] || entry[:reply_context] || %{}),
      chunk_attempt_label(entry["chunk_count"] || entry[:chunk_count])
    ]
    |> Enum.reject(&is_nil_or_empty/1)
    |> Enum.join(" · ")
  end

  defp turn_attachments(turn) do
    metadata = turn.metadata || %{}
    metadata["attachments"] || metadata[:attachments] || []
  end

  defp attachment_label(attachment) do
    kind = attachment["kind"] || attachment[:kind] || "attachment"
    file_name = attachment["file_name"] || attachment[:file_name]
    ref = attachment_ref_label(attachment)

    base =
      if is_binary(file_name) and file_name != "" do
        "#{kind}: #{file_name}"
      else
        kind
      end

    case ref do
      nil -> base
      value -> "#{base} · #{value}"
    end
  end

  defp attachment_ref_label(attachment) do
    ref =
      attachment["download_ref"] || attachment[:download_ref] ||
        attachment["source_url"] || attachment[:source_url]

    cond do
      not is_binary(ref) or ref == "" ->
        nil

      String.starts_with?(ref, "http://") or String.starts_with?(ref, "https://") ->
        uri = URI.parse(ref)
        host = uri.host || "external"
        path = uri.path || ""
        "#{host}#{String.slice(path, 0, 24)}"

      true ->
        String.slice(ref, 0, 36)
    end
  end

  defp retry_count_label(count) when is_integer(count) and count > 0, do: "retry #{count}"
  defp retry_count_label(_count), do: nil

  defp transport_label(value) when is_binary(value) and value != "", do: "transport #{value}"
  defp transport_label(_value), do: nil

  defp transport_topic_label(value) when is_binary(value) and value != "", do: "topic #{value}"
  defp transport_topic_label(_value), do: nil

  defp message_ids_label(ids) when is_list(ids) and length(ids) > 1, do: "msg ids #{length(ids)}"
  defp message_ids_label(_ids), do: nil

  defp next_retry_label(%DateTime{} = value), do: "next retry #{format_delivery_time(value)}"
  defp next_retry_label(value) when is_binary(value), do: "next retry #{value}"
  defp next_retry_label(_value), do: nil

  defp dead_letter_label(%DateTime{} = value), do: "dead letter #{format_delivery_time(value)}"
  defp dead_letter_label(value) when is_binary(value), do: "dead letter #{value}"
  defp dead_letter_label(_value), do: nil

  defp reply_context_attempt_label(context) when is_map(context) do
    [
      context["thread_ts"] || context[:thread_ts],
      context["reply_to_message_id"] || context[:reply_to_message_id]
    ]
    |> Enum.reject(&is_nil_or_empty/1)
    |> case do
      [] -> nil
      values -> Enum.join(values, "/")
    end
  end

  defp reply_context_attempt_label(_context), do: nil

  defp chunk_attempt_label(count) when is_integer(count) and count > 1, do: "chunks #{count}"
  defp chunk_attempt_label(_count), do: nil

  defp format_delivery_time(%DateTime{} = value),
    do: Calendar.strftime(value, "%Y-%m-%d %H:%M:%S UTC")

  defp format_delivery_time(value) when is_binary(value), do: value
  defp format_delivery_time(_value), do: "unknown"

  defp fetch_agent(nil), do: {:error, :missing_agent}
  defp fetch_agent(""), do: {:error, :missing_agent}

  defp fetch_agent(id) do
    {:ok, Runtime.get_agent!(id)}
  rescue
    Ecto.NoResultsError -> {:error, :agent_not_found}
  end

  defp submit_reply(_agent, _conversation, message, _metadata, _action)
       when message in [nil, ""] do
    {:error, :empty_message}
  end

  defp submit_reply(agent, conversation, message, metadata, action) do
    case HydraX.Agent.Channel.submit(agent, conversation, message, metadata) do
      {:deferred, reason} ->
        {:ok, Runtime.get_conversation!(conversation.id), "Reply deferred: #{reason}"}

      _response ->
        flash_message = if action == :start, do: "Conversation started", else: "Reply sent"
        {:ok, Runtime.get_conversation!(conversation.id), flash_message}
    end
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

  defp channel_steps(nil), do: []
  defp channel_steps(%{steps: steps}) when is_list(steps), do: steps
  defp channel_steps(%{plan: %{"steps" => steps}}) when is_list(steps), do: steps
  defp channel_steps(_), do: []

  defp channel_skill_hints(nil), do: []
  defp channel_skill_hints(%{plan: %{"skill_hints" => hints}}) when is_list(hints), do: hints
  defp channel_skill_hints(_), do: []

  defp channel_tool_results(nil), do: []
  defp channel_tool_results(%{tool_results: results}) when is_list(results), do: results
  defp channel_tool_results(_), do: []

  defp channel_execution_events(nil), do: []

  defp channel_execution_events(%{execution_events: events}) when is_list(events),
    do: Enum.reverse(events)

  defp channel_execution_events(_), do: []

  defp channel_plan_summary(nil), do: "No execution checkpoint yet."
  defp channel_plan_summary(%{plan: plan}) when plan == %{}, do: "No execution checkpoint yet."

  defp channel_plan_summary(%{plan: %{"mode" => mode, "latest_message" => message}}) do
    message = message || "No user message captured yet."

    case mode do
      "direct" -> "Direct-response turn. Latest message: #{message}"
      "tool_capable" -> "Tool-capable turn. Latest message: #{message}"
      _ -> message
    end
  end

  defp channel_event_summary(%{"phase" => phase, "details" => details}) when is_map(details) do
    case phase do
      "planned" ->
        details["summary"] || "Execution plan prepared"

      "provider_requested" ->
        "requested #{details["provider"] || "provider"} (#{details["tooling"] || "direct"})"

      "provider_tool_request" ->
        "provider requested #{details["tool_count"] || 0} tool calls in round #{details["round"] || 0}"

      "tool_result" ->
        "#{details["tool_name"] || "tool"} #{if(details["is_error"], do: "failed", else: "succeeded")}: #{details["summary"] || "completed"}"

      "tool_cache_hit" ->
        "reused #{details["cache_hits"] || 0} cached tool result(s); #{details["cache_misses"] || 0} fresh execution(s)"

      "provider_succeeded" ->
        "provider #{details["provider"] || "unknown"} returned #{details["stop_reason"] || "response"}"

      "provider_completed" ->
        "final response via #{details["provider"] || "unknown"}"

      "provider_failed" ->
        "provider request failed: #{details["reason"] || "unknown"}"

      "stream_started" ->
        "stream opened via #{details["provider"] || "unknown"}"

      "stream_completed" ->
        "stream completed via #{details["provider"] || "unknown"}"

      "ownership_handoff_pending" ->
        "waiting for #{details["awaiting"] || "handoff"} on #{details["owner"] || "new owner"}"

      "handoff_restart" ->
        waiting_for = details["waiting_for"] || "handoff"
        captured_chars = details["captured_chars"] || 0
        captured_chunks = details["captured_chunks"] || 0

        "resumed after #{waiting_for}; preserved #{captured_chars} chars across #{captured_chunks} chunks"

      "handoff_response_replayed" ->
        details["summary"] || "Completed a captured response after handoff"

      "recovered_after_restart" ->
        details["summary"] || "Recovered pending execution after restart"

      _ ->
        details["summary"] || inspect(details)
    end
  end

  defp channel_event_summary(_event), do: "Execution event recorded"

  defp event_detail_labels(%{"details" => details}) when is_map(details) do
    []
    |> maybe_add_step_label(details["kind"])
    |> maybe_add_step_label(details["name"])
    |> maybe_add_step_label(details["lifecycle"])
    |> maybe_add_step_label(details["result_source"])
    |> maybe_add_step_label(if(details["cached"], do: "cached", else: nil))
    |> maybe_add_step_label(if(details["replayed"], do: "replayed", else: nil))
    |> maybe_add_step_label(step_tool_use_label(details["tool_use_id"]))
    |> maybe_add_step_label(details["round"] && "round #{details["round"]}")
  end

  defp event_detail_labels(_event), do: []

  defp step_detail_labels(step) when is_map(step) do
    []
    |> maybe_add_step_label(step_attempt_label(step["attempt_count"]))
    |> maybe_add_step_label(step_retry_label(step["retry_state"]))
    |> maybe_add_step_label(if(step["cached"], do: "cached", else: nil))
    |> maybe_add_step_label(step["lifecycle"])
    |> maybe_add_step_label(step["result_source"])
    |> maybe_add_step_label(replay_count_label(step["replay_count"]))
    |> maybe_add_step_label(step_tool_use_label(step["tool_use_id"]))
    |> maybe_add_step_label(step["safety_classification"])
    |> maybe_add_step_label(step_started_label(step["last_started_at"] || step["started_at"]))
    |> maybe_add_step_label(step_finished_label(step))
    |> maybe_add_step_label(step_updated_label(step["updated_at"]))
  end

  defp step_detail_labels(_), do: []

  defp maybe_add_step_label(labels, nil), do: labels
  defp maybe_add_step_label(labels, ""), do: labels
  defp maybe_add_step_label(labels, label), do: labels ++ [label]

  defp step_updated_label(nil), do: nil
  defp step_updated_label(value), do: "updated #{format_event_time(value)}"

  defp step_attempt_label(nil), do: nil
  defp step_attempt_label(0), do: nil
  defp step_attempt_label(1), do: "attempt 1"
  defp step_attempt_label(value) when is_integer(value), do: "attempt #{value}"

  defp step_retry_label(%{"retry_count" => value}) when is_integer(value) and value > 0,
    do: "retry #{value}"

  defp step_retry_label(_retry_state), do: nil

  defp step_retry_summary(%{"retry_state" => retry_state}) when is_map(retry_state) do
    values =
      [
        retry_state["last_status"],
        retry_state["attempt_count"] && "attempts #{retry_state["attempt_count"]}",
        retry_state["retry_count"] && "retries #{retry_state["retry_count"]}",
        retry_state["result_source"] && "source #{retry_state["result_source"]}",
        retry_state["last_error"] && "error #{retry_state["last_error"]}"
      ]
      |> Enum.reject(&(&1 in [nil, "", false]))

    case values do
      [] -> nil
      _ -> "Retry state: " <> Enum.join(values, " · ")
    end
  end

  defp step_retry_summary(_step), do: nil

  defp step_attempt_history_summary(%{"attempt_history" => history})
       when is_list(history) and history != [] do
    attempts =
      history
      |> Enum.map(&format_step_attempt/1)
      |> Enum.reject(&is_nil_or_empty/1)

    case attempts do
      [] -> nil
      _ -> "Attempts: " <> Enum.join(attempts, " -> ")
    end
  end

  defp step_attempt_history_summary(_step), do: nil

  defp format_step_attempt(%{} = attempt) do
    status = attempt["status"] || "unknown"
    at = attempt["at"] || attempt[:at]
    error = attempt["error"] || attempt[:error]

    [status, at && format_event_time(at), error && "error #{error}"]
    |> Enum.reject(&is_nil_or_empty/1)
    |> Enum.join(" ")
  end

  defp format_step_attempt(_attempt), do: nil

  defp replay_count_label(nil), do: nil
  defp replay_count_label(0), do: nil
  defp replay_count_label(value) when is_integer(value), do: "replay #{value}"

  defp step_tool_use_label(nil), do: nil
  defp step_tool_use_label(value) when is_binary(value), do: "tool use #{value}"

  defp step_started_label(nil), do: nil
  defp step_started_label(value), do: "started #{format_event_time(value)}"

  defp step_finished_label(%{"completed_at" => value}) when not is_nil(value),
    do: "finished #{format_event_time(value)}"

  defp step_finished_label(%{"failed_at" => value}) when not is_nil(value),
    do: "failed #{format_event_time(value)}"

  defp step_finished_label(_step), do: nil

  defp format_event_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%H:%M:%S")
  defp format_event_time(value) when is_binary(value), do: String.slice(value, 11, 8)
  defp format_event_time(_value), do: "now"

  defp channel_recovery_summary(nil), do: nil

  defp channel_recovery_summary(%{recovery_lineage: lineage})
       when is_map(lineage) and lineage != %{} do
    "Recovery lineage: turn #{lineage["turn_scope_id"] || "n/a"} · recoveries #{lineage["recovery_count"] || 0} · cache hits #{lineage["cache_hits"] || 0} · cache misses #{lineage["cache_misses"] || 0}"
  end

  defp channel_recovery_summary(_state), do: nil

  defp channel_ownership_summary(%{ownership: ownership}) when is_map(ownership) do
    values =
      [
        ownership["mode"],
        ownership["owner"],
        ownership["stage"],
        ownership["contended"] && "contended"
      ]
      |> Enum.reject(&(&1 in [nil, ""]))

    if values == [], do: nil, else: "Owner: " <> Enum.join(values, " · ")
  end

  defp channel_ownership_summary(_state), do: nil

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

  defp channel_handoff_summary(nil), do: nil

  defp channel_handoff_summary(%{handoff: handoff}) when is_map(handoff) and handoff != %{} do
    waiting_for = handoff["waiting_for"] || "handoff"
    owner = handoff["owner"] || "owner"
    "Ownership handoff pending: waiting for #{waiting_for} on #{owner}"
  end

  defp channel_handoff_summary(_state), do: nil

  defp channel_resume_summary(nil), do: nil
  defp channel_resume_summary(%{resume_stage: nil}), do: nil

  defp channel_resume_summary(%{resume_stage: "streaming", stale_stream: true}) do
    "Stale streaming checkpoint detected: owner-side replay can resume this conversation."
  end

  defp channel_resume_summary(%{resume_stage: stage}) do
    "Recoverable runtime state: #{stage}"
  end

  defp channel_pending_response_summary(nil), do: nil

  defp channel_pending_response_summary(%{pending_response: response})
       when is_map(response) and response != %{} do
    provider = get_in(response, ["metadata", "provider"]) || "provider"
    content = response["content"] || ""
    "Pending provider response from #{provider}: #{String.slice(content, 0, 120)}"
  end

  defp channel_pending_response_summary(_state), do: nil

  defp channel_stream_capture(nil), do: nil

  defp channel_stream_capture(%{stream_capture: capture}) when is_map(capture) and capture != %{},
    do: capture

  defp channel_stream_capture(_state), do: nil

  defp channel_stream_capture_labels(state) do
    capture = channel_stream_capture(state) || %{}

    []
    |> maybe_add_step_label(capture["provider"])
    |> maybe_add_step_label(stream_capture_chunks_label(capture["chunk_count"]))
    |> maybe_add_step_label(stream_capture_time_label(capture["captured_at"]))
  end

  defp stream_capture_preview(nil), do: nil
  defp stream_capture_preview(%{"content" => content}) when is_binary(content), do: content
  defp stream_capture_preview(_capture), do: nil

  defp stream_capture_chunks_label(count) when is_integer(count) and count > 0,
    do: "chunks #{count}"

  defp stream_capture_chunks_label(_count), do: nil

  defp stream_capture_time_label(nil), do: nil
  defp stream_capture_time_label(value), do: "captured #{format_event_time(value)}"

  defp step_status_label("running", true), do: "current"

  defp step_status_label(status, _current?)
       when status in ["pending", "running", "completed", "failed"], do: status

  defp step_status_label(_status, _current?), do: "pending"

  defp step_status_class("completed", _),
    do: "border-emerald-400/20 bg-emerald-400/10 text-emerald-200"

  defp step_status_class("failed", _), do: "border-rose-400/20 bg-rose-400/10 text-rose-200"
  defp step_status_class("running", true), do: "border-cyan-400/20 bg-cyan-400/10 text-cyan-200"
  defp step_status_class("running", _), do: "border-cyan-400/20 bg-cyan-400/10 text-cyan-200"
  defp step_status_class(_, _), do: "border-white/10 bg-black/10 text-[var(--hx-mute)]"

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

  defp is_nil_or_empty(nil), do: true
  defp is_nil_or_empty(""), do: true
  defp is_nil_or_empty(_value), do: false

  defp rename_form(nil), do: to_form(%{"title" => ""}, as: :rename)
  defp rename_form(conversation), do: to_form(%{"title" => conversation.title || ""}, as: :rename)

  defp blank_to_default(nil, default), do: default
  defp blank_to_default("", default), do: default
  defp blank_to_default(value, _default), do: value

  defp compaction_label(nil), do: "No compaction data available"

  defp compaction_label(compaction) do
    level = compaction.level || "idle"
    ratio = round((compaction.token_ratio || 0.0) * 100)

    "#{compaction.turn_count} turns · #{compaction.estimated_tokens || 0}/#{compaction.conversation_limit_tokens || 0} tokens · #{ratio}% · #{level}"
  end

  defp compaction_thresholds_label(%{soft: soft, medium: medium, hard: hard}) do
    "soft #{soft} or 80% · medium #{medium} or 90% · hard #{hard} or 95%"
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
