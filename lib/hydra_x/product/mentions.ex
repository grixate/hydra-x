defmodule HydraX.Product.Mentions do
  @moduledoc """
  Create and dispatch @-mentions. Spec §5 of the task-data-model.

  Parser: `@<agent_id>` tokens where `agent_id` matches a known agent. If a
  mention has `intent = request_task`, a new `AgentTask` is auto-created for
  the target agent, and the resulting Flow is recomputed.
  """

  import Ecto.Query

  alias HydraX.Repo
  alias HydraX.Product.AgentBridge
  alias HydraX.Product.AgentTask
  alias HydraX.Product.AgentTasks
  alias HydraX.Product.Flows
  alias HydraX.Product.Mention
  alias HydraX.Product.ProductMessage
  alias HydraX.Product.PubSub, as: ProductPubSub

  # Agent IDs recognised by the parser. Must stay in sync with the Zone 1 list.
  @known_agents ~w(researcher strategist architect designer memory_agent coherence continuous_research)

  @mention_regex ~r/(^|\W)@([a-z_]+)/i

  @doc "All known agent IDs the parser will recognise."
  def known_agents, do: @known_agents

  @doc "Return the list of agent IDs referenced in `text`."
  @spec parse_agents(String.t() | nil) :: [String.t()]
  def parse_agents(nil), do: []

  def parse_agents(text) when is_binary(text) do
    Regex.scan(@mention_regex, text, capture: :all_but_first)
    |> Enum.map(fn [_, agent] -> String.downcase(agent) end)
    |> Enum.filter(&(&1 in @known_agents))
    |> Enum.uniq()
  end

  @doc """
  Infer the @-mention intent from surrounding language (spec §8).

  Returns `{intent, confidence}` where intent is one of
  `"request_task"`, `"share_context"`, `"request_input"`, `"notify"`
  and confidence is `:low | :medium | :high`.

  Heuristic: keywords from the message body drive the classification.
  Low-confidence results flag the client to surface a disambiguation
  prompt rather than silently dispatching side effects.
  """
  @spec infer_intent(String.t() | nil) :: {String.t(), :low | :medium | :high}
  def infer_intent(nil), do: {"share_context", :low}

  def infer_intent(text) when is_binary(text) do
    lower = String.downcase(text)

    cond do
      has_any?(lower, ["fyi", "for your info", "heads up", "just so you know"]) ->
        {"share_context", :high}

      has_any?(lower, ["what do you think", "thoughts?", "opinion", "would you"]) ->
        {"request_input", :high}

      has_any?(lower, [
        "can you",
        "could you",
        "please ",
        "look into",
        "investigate",
        "check this",
        "check it",
        "find out",
        "dig into",
        "analyse",
        "analyze"
      ]) ->
        {"request_task", :high}

      String.contains?(lower, "?") ->
        {"request_input", :medium}

      true ->
        {"share_context", :low}
    end
  end

  defp has_any?(haystack, needles) do
    Enum.any?(needles, &String.contains?(haystack, &1))
  end

  ## Creation

  @doc """
  Create a mention and apply its side effects per `intent`.

  For `request_task`:
    * creates a new AgentTask for the target agent in `pending`
    * stores the new task id on the mention's `target_task_id`
    * registers the pair in a Flow (new or existing)
  """
  def create_mention(attrs) do
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)

    changeset = Mention.changeset(%Mention{}, attrs)

    case Repo.insert(changeset) do
      {:ok, mention} ->
        mention = dispatch_side_effects(mention)
        broadcast(mention, "mention.created")
        {:ok, mention}

      err ->
        err
    end
  end

  @valid_intents ~w(request_task share_context request_input notify)

  @doc """
  Update a mention's intent (e.g. after the user resolves an ambiguous
  inference). Re-runs side-effects if the new intent is `request_task`
  and no task has been spawned yet, so the task creation happens on the
  user's confirmation rather than silently at parse time.
  """
  def update_intent(%Mention{} = mention, new_intent) when new_intent in @valid_intents do
    attrs = %{
      "intent" => new_intent,
      "metadata" => Map.put(mention.metadata || %{}, "ambiguous_intent", false)
    }

    with {:ok, updated} <- mention |> Mention.changeset(attrs) |> Repo.update() do
      updated =
        if new_intent == "request_task" and is_nil(updated.target_task_id) do
          dispatch_side_effects(updated)
        else
          updated
        end

      broadcast(updated, "mention.updated")
      {:ok, updated}
    end
  end

  def update_intent(%Mention{}, _), do: {:error, :invalid_intent}

  def get_mention(id), do: Repo.get(Mention, id)

  @doc """
  Called from `AgentTasks.transition` when a task reaches `completed`.
  If the task was spawned by a chat @-mention, post a follow-up system
  message into the source conversation linking to the target thread.
  """
  def emit_task_completion_followup(%AgentTask{originating_mention_id: nil}), do: :skip

  def emit_task_completion_followup(%AgentTask{} = task) do
    case Repo.get(Mention, task.originating_mention_id) do
      nil ->
        :skip

      %Mention{source_type: "chat_message"} = mention ->
        with source_conv_id when is_integer(source_conv_id) <- source_conversation_id(mention) do
          target_conv_id = target_conversation_id(mention)

          content = "#{pretty_agent(task.agent_id)} finished: #{task.title}"

          metadata = %{
            "kind" => "mention_task_completed",
            "mention_id" => mention.id,
            "target_agent" => task.agent_id,
            "target_task_id" => task.id,
            "target_conversation_id" => target_conv_id
          }

          insert_system_message!(source_conv_id, task.project_id, content, metadata)
        end

      _ ->
        :skip
    end
  end

  ## Queries

  def list_for_task(task_id) do
    task_id = to_int(task_id)

    Mention
    |> where([m], m.source_task_id == ^task_id or m.target_task_id == ^task_id)
    |> order_by([m], asc: m.inserted_at)
    |> Repo.all()
  end

  ## Private

  defp dispatch_side_effects(%Mention{intent: "request_task"} = mention) do
    source_task = if mention.source_task_id, do: Repo.get(AgentTask, mention.source_task_id)

    title =
      mention.content
      |> to_string()
      |> String.split(~r/\n|\./)
      |> List.first()
      |> String.trim()
      |> case do
        "" -> "@#{mention.target_agent_id} task"
        t -> String.slice(t, 0, 120)
      end

    assigned_by =
      cond do
        mention.source_user_id -> "user"
        mention.source_agent_id -> "agent"
        true -> "system"
      end

    attrs = %{
      project_id: mention.project_id,
      agent_id: mention.target_agent_id,
      title: title,
      description: mention.content,
      state: "pending",
      priority: (source_task && source_task.priority) || "normal",
      assigned_by: assigned_by,
      assigned_by_user_id: mention.source_user_id,
      assigned_by_agent_id: mention.source_agent_id,
      parent_task_id: mention.source_task_id,
      originating_mention_id: mention.id
    }

    case AgentTasks.create_task(attrs) do
      {:ok, task} ->
        updated =
          mention
          |> Mention.changeset(%{"target_task_id" => task.id})
          |> Repo.update!()

        Flows.register_mention(updated, source_task, task)
        post_source_reference(updated, task)
        updated

      {:error, changeset} ->
        # Task spawn failed — record it so the mention isn't silently
        # orphaned. The mention row stays (audit trail) but the caller
        # can detect via `target_task_id == nil`.
        require Logger

        Logger.warning(
          "[Mentions] request_task failed for mention=#{mention.id} " <>
            "target=#{mention.target_agent_id}: #{inspect(changeset.errors)}"
        )

        post_spawn_failure_reference(mention, changeset)
        mention
    end
  end

  defp dispatch_side_effects(%Mention{intent: "share_context"} = mention) do
    post_target_context_share(mention)
    mention
  end

  defp dispatch_side_effects(mention), do: mention

  ## Cross-thread system messages
  #
  # When an @-mention fans work out to another agent, emit a system-role
  # message into the originating chat thread so the user sees continuity
  # without leaving the source conversation (spec chat-architecture §8
  # Scenario A). Mirrored for share_context into the target thread.

  defp post_source_reference(%Mention{source_type: "chat_message"} = mention, task) do
    with %ProductMessage{} = source_msg <- source_message(mention) do
      content = "#{pretty_agent(mention.target_agent_id)} will handle this."

      metadata = %{
        "kind" => "mention_spawned_task",
        "mention_id" => mention.id,
        "target_agent" => mention.target_agent_id,
        "target_task_id" => task.id,
        "target_conversation_id" => target_conversation_id(mention)
      }

      insert_system_message!(
        source_msg.product_conversation_id,
        mention.project_id,
        content,
        metadata
      )
    end
  end

  defp post_source_reference(_, _), do: :skip

  defp post_spawn_failure_reference(%Mention{source_type: "chat_message"} = mention, changeset) do
    with %ProductMessage{} = source_msg <- source_message(mention) do
      content = "Couldn't assign this to #{pretty_agent(mention.target_agent_id)} — retry?"

      metadata = %{
        "kind" => "mention_spawn_failed",
        "mention_id" => mention.id,
        "target_agent" => mention.target_agent_id,
        "errors" => inspect(changeset.errors)
      }

      insert_system_message!(
        source_msg.product_conversation_id,
        mention.project_id,
        content,
        metadata
      )
    end
  end

  defp post_spawn_failure_reference(_, _), do: :skip

  defp post_target_context_share(%Mention{source_type: "chat_message"} = mention) do
    with target_conversation_id when is_integer(target_conversation_id) <-
           target_conversation_id(mention) do
      source_label =
        cond do
          mention.source_agent_id -> "#{pretty_agent(mention.source_agent_id)} shared context"
          mention.source_user_id -> "Shared context"
          true -> "Context shared"
        end

      content = "#{source_label}: #{truncate(mention.content, 200)}"

      metadata = %{
        "kind" => "mention_context_share",
        "mention_id" => mention.id,
        "source_agent" => mention.source_agent_id,
        "source_conversation_id" => source_conversation_id(mention)
      }

      insert_system_message!(target_conversation_id, mention.project_id, content, metadata)
    end
  end

  defp post_target_context_share(_), do: :skip

  defp source_message(%Mention{source_message_id: nil}), do: nil
  defp source_message(%Mention{source_message_id: id}), do: Repo.get(ProductMessage, id)

  defp source_conversation_id(%Mention{} = mention) do
    case source_message(mention) do
      %ProductMessage{product_conversation_id: id} -> id
      _ -> nil
    end
  end

  defp target_conversation_id(%Mention{} = mention) do
    case AgentBridge.ensure_project_conversation(mention.project_id, mention.target_agent_id, %{
           "channel" => "chat_dock",
           "external_ref" => "chat_dock",
           "metadata" => %{"kind" => "chat_dock"}
         }) do
      {:ok, %{id: id}} -> id
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp insert_system_message!(conversation_id, project_id, content, metadata) do
    {:ok, message} =
      %ProductMessage{}
      |> ProductMessage.changeset(%{
        "product_conversation_id" => conversation_id,
        "role" => "system",
        "content" => content,
        "metadata" => metadata
      })
      |> Repo.insert()

    ProductPubSub.broadcast_project_event(project_id, "chat.message_inserted", %{
      conversation_id: conversation_id,
      message: message
    })

    message
  end

  defp pretty_agent(id),
    do:
      id
      |> String.replace("_", " ")
      |> String.split()
      |> Enum.map(&String.capitalize/1)
      |> Enum.join(" ")

  defp truncate(nil, _), do: ""

  defp truncate(text, n) when is_binary(text) do
    if String.length(text) <= n, do: text, else: String.slice(text, 0, n - 1) <> "…"
  end

  defp broadcast(mention, event) do
    ProductPubSub.broadcast_project_event(mention.project_id, event, %{mention: mention})
  end

  defp to_int(v) when is_integer(v), do: v
  defp to_int(v) when is_binary(v), do: String.to_integer(v)
end
