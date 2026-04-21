defmodule HydraX.Coherence do
  @moduledoc """
  Cycle 2 hero — continuously-running service agent that surfaces
  contradictions across the graph.

  This context covers:
    * CRUD on `Contradiction` + `ContradictionEvent`
    * Status transitions (open → under_review → resolved | dismissed |
      stale | acknowledged_tension) with audit logging
    * Lifecycle triggers for the `DetectionService`

  Detection itself lives in `HydraX.Coherence.DetectionService` —
  invoked from `AgentTasks` transitions, `SharedMemory` mutations, and
  the scheduler. Keeps the public context decoupled from LLM details.
  """

  import Ecto.Query

  alias HydraX.Repo
  alias HydraX.Coherence.Contradiction
  alias HydraX.Coherence.ContradictionEvent
  alias HydraX.Product.AgentRules
  alias HydraX.Product.PubSub, as: ProductPubSub

  @visible_statuses ~w(open under_review acknowledged_tension)

  ## ------------------------------------------------------------------
  ## Queries
  ## ------------------------------------------------------------------

  @doc """
  List open/visible contradictions for a project. Spec §6: severity >=
  medium appears in Stream Blockers; all statuses surface in CC Zone 3.
  """
  def list_for_project(project_id, opts \\ []) do
    project_id = to_int(project_id)

    Contradiction
    |> where([c], c.project_id == ^project_id)
    |> apply_status_filter(opts[:status])
    |> apply_severity_floor(opts[:min_severity])
    |> order_by([c], desc: c.detected_at)
    |> limit(^(opts[:limit] || 100))
    |> Repo.all()
  end

  def list_visible(project_id, opts \\ []) do
    list_for_project(project_id, Keyword.put(opts, :status, @visible_statuses))
  end

  def list_for_node(node_type, node_id) do
    # `node_a_id` / `node_b_id` are integer columns. Non-integer inputs
    # — e.g. a future UUID-keyed shared-memory node — return `[]`
    # instead of crashing on type mismatch.
    case safe_node_id(node_id) do
      {:ok, id_int} ->
        Contradiction
        |> where(
          [c],
          (c.node_a_type == ^to_string(node_type) and c.node_a_id == ^id_int) or
            (c.node_b_type == ^to_string(node_type) and c.node_b_id == ^id_int)
        )
        |> where([c], c.status in ^@visible_statuses)
        |> Repo.all()

      :skip ->
        []
    end
  end

  defp safe_node_id(id) when is_integer(id), do: {:ok, id}

  defp safe_node_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {n, ""} -> {:ok, n}
      _ -> :skip
    end
  end

  defp safe_node_id(_), do: :skip

  def get!(id), do: Repo.get!(Contradiction, id)
  def get(id), do: Repo.get(Contradiction, id)

  @doc "Badge count per node type (used for graph overlay rendering)."
  def badge_counts_for_project(project_id) do
    project_id = to_int(project_id)

    from(c in Contradiction,
      where: c.project_id == ^project_id and c.status in ^@visible_statuses,
      select: {c.node_a_type, c.node_a_id, c.severity}
    )
    |> Repo.all()
    |> Enum.reduce(%{}, fn {type, id, severity}, acc ->
      Map.update(acc, {to_string(type), id}, [severity], &[severity | &1])
    end)
  end

  ## ------------------------------------------------------------------
  ## Creation / upsert (invoked by DetectionService)
  ## ------------------------------------------------------------------

  @doc """
  Record a newly-detected contradiction. On re-detection of an existing
  pair that had been dismissed, bumps `dismissed_count` and resurfaces.

  Normalises the (A, B) pair order (by `{node_type, node_id}` ascending)
  so "A contradicts B" and "B contradicts A" collapse to a single row.
  Without normalisation a detection run picking either order would
  create two logically-identical contradictions.
  """
  def record_detection(attrs) do
    attrs =
      attrs
      |> Map.new(fn {k, v} -> {to_string(k), v} end)
      |> Map.put_new("detected_at", DateTime.utc_now())
      |> Map.put_new("last_confirmed_at", DateTime.utc_now())
      |> normalise_pair_order()

    if filtered_by_rules?(attrs) do
      {:error, :filtered}
    else
      do_record_detection(attrs)
    end
  end

  defp do_record_detection(attrs) do
    case find_existing_pair(attrs) do
      nil ->
        case %Contradiction{} |> Contradiction.changeset(attrs) |> Repo.insert() do
          {:ok, contradiction} ->
            log_event(contradiction, "detected", %{}, system_actor())
            broadcast(contradiction, "contradiction.detected")
            {:ok, contradiction}

          err ->
            err
        end

      %Contradiction{status: "dismissed"} = prior ->
        prior
        |> Contradiction.changeset(%{
          "status" => "open",
          "last_confirmed_at" => DateTime.utc_now(),
          "dismissed_count" => prior.dismissed_count + 1,
          "explanation" => attrs["explanation"] || prior.explanation,
          "severity" => attrs["severity"] || prior.severity,
          "confidence" => attrs["confidence"] || prior.confidence
        })
        |> Repo.update()
        |> case do
          {:ok, updated} ->
            # Spec §11: three dismissals → stop auto-surfacing.
            if updated.dismissed_count >= 3 do
              {:ok, auto} =
                updated
                |> Contradiction.changeset(%{"status" => "dismissed", "status_reason" => "auto-silenced after 3 dismissals"})
                |> Repo.update()

              log_event(auto, "dismissed", %{"auto" => true}, system_actor())
              {:ok, auto}
            else
              log_event(updated, "re_detected", %{}, system_actor())
              broadcast(updated, "contradiction.re_detected")
              {:ok, updated}
            end

          err ->
            err
        end

      %Contradiction{} = prior ->
        # Already open — just bump last_confirmed_at.
        prior
        |> Contradiction.changeset(%{"last_confirmed_at" => DateTime.utc_now()})
        |> Repo.update()
        |> case do
          {:ok, updated} ->
            log_event(updated, "re_confirmed", %{}, system_actor())
            {:ok, updated}

          err ->
            err
        end
    end
  end

  # Apply coherence agent rules at detection time. `mute_category` is
  # matched against the contradiction's `mode`; `ignore_pattern` is
  # matched (case-insensitive substring) against the explanation text.
  defp filtered_by_rules?(%{"project_id" => project_id} = attrs) when not is_nil(project_id) do
    index = AgentRules.rules_index(project_id, "coherence")

    cond do
      map_size(index) == 0 -> false
      AgentRules.muted?(index, attrs["mode"]) -> true
      AgentRules.ignored?(index, attrs["explanation"] || "") -> true
      true -> false
    end
  end

  defp filtered_by_rules?(_attrs), do: false

  defp find_existing_pair(attrs) do
    Contradiction
    |> where(
      [c],
      c.mode == ^attrs["mode"] and
        c.node_a_type == ^to_string(attrs["node_a_type"]) and c.node_a_id == ^attrs["node_a_id"] and
        c.node_b_type == ^to_string(attrs["node_b_type"]) and c.node_b_id == ^attrs["node_b_id"]
    )
    |> order_by([c], desc: c.inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  # Deterministic ordering: the "smaller" (type, id) goes to slot A.
  # Keeps pair-lookup + the partial unique index in agreement regardless
  # of which side the LLM scan discovered first.
  defp normalise_pair_order(attrs) do
    a = {to_string(attrs["node_a_type"] || ""), attrs["node_a_id"] || 0, attrs["node_a_scope"] || "project"}
    b = {to_string(attrs["node_b_type"] || ""), attrs["node_b_id"] || 0, attrs["node_b_scope"] || "project"}

    if a <= b do
      attrs
    else
      attrs
      |> Map.put("node_a_type", elem(b, 0))
      |> Map.put("node_a_id", elem(b, 1))
      |> Map.put("node_a_scope", elem(b, 2))
      |> Map.put("node_b_type", elem(a, 0))
      |> Map.put("node_b_id", elem(a, 1))
      |> Map.put("node_b_scope", elem(a, 2))
    end
  end

  ## ------------------------------------------------------------------
  ## User actions
  ## ------------------------------------------------------------------

  def dismiss(%Contradiction{} = c, opts \\ []) do
    transition(c, "dismissed", opts)
  end

  def resolve(%Contradiction{} = c, opts \\ []) do
    attrs = %{
      "status" => "resolved",
      "status_reason" => opts[:reason],
      "resolved_at" => DateTime.utc_now(),
      "resolved_by_user_id" => opts[:user_id]
    }

    with {:ok, updated} <- c |> Contradiction.changeset(attrs) |> Repo.update() do
      log_event(updated, "resolved", %{"reason" => opts[:reason]}, actor(opts))
      broadcast(updated, "contradiction.resolved")
      {:ok, updated}
    end
  end

  def acknowledge_tension(%Contradiction{} = c, opts \\ []) do
    transition(c, "acknowledged_tension", opts)
  end

  def mark_under_review(%Contradiction{} = c, opts \\ []) do
    transition(c, "under_review", opts)
  end

  def mark_stale(%Contradiction{} = c, opts \\ []) do
    transition(c, "stale", Keyword.put_new(opts, :reason, "auto-stale"))
  end

  def transition(%Contradiction{} = c, new_status, opts) do
    attrs = %{
      "status" => new_status,
      "status_reason" => opts[:reason]
    }

    with {:ok, updated} <- c |> Contradiction.changeset(attrs) |> Repo.update() do
      log_event(updated, new_status, %{"reason" => opts[:reason]}, actor(opts))
      broadcast(updated, "contradiction.#{new_status}")
      {:ok, updated}
    end
  end

  ## ------------------------------------------------------------------
  ## Helpers
  ## ------------------------------------------------------------------

  defp log_event(contradiction, event_type, payload, actor) do
    %ContradictionEvent{}
    |> ContradictionEvent.changeset(%{
      contradiction_id: contradiction.id,
      event_type: event_type,
      payload: payload,
      actor_type: actor.type,
      actor_id: actor.id
    })
    |> Repo.insert()
  end

  defp broadcast(%Contradiction{project_id: nil}, _event), do: :ok

  defp broadcast(%Contradiction{} = c, event) do
    ProductPubSub.broadcast_project_event(c.project_id, event, %{contradiction: c})
    if event == "contradiction.detected", do: post_coherence_chat_message(c)
    :ok
  end

  # Coherence chat seed — on detection, post a system-role message into
  # the project's memory_agent conversation so the finding shows up in
  # the user's chat flow alongside the toast. Best-effort; any failure
  # is swallowed so the detection path stays resilient.
  defp post_coherence_chat_message(%Contradiction{severity: "low"}), do: :skip

  defp post_coherence_chat_message(%Contradiction{} = c) do
    Task.start(fn ->
      try do
        do_post_coherence_chat_message(c)
      rescue
        _ -> :ok
      end
    end)
  end

  defp do_post_coherence_chat_message(%Contradiction{} = c) do
    project = HydraX.Repo.get(HydraX.Product.Project, c.project_id)

    if is_nil(project) or is_nil(project.memory_agent_id) do
      :skip
    else
      post_coherence_chat_message_with_project(c)
    end
  end

  defp post_coherence_chat_message_with_project(%Contradiction{} = c) do
    case HydraX.Product.AgentBridge.ensure_project_conversation(
           c.project_id,
           "memory_agent",
           %{
             "channel" => "coherence_feed",
             "external_ref" => "coherence_feed",
             "title" => "Coherence",
             "metadata" => %{"kind" => "coherence_feed"}
           }
         ) do
      {:ok, conversation} ->
        content =
          "Coherence found a #{c.severity} contradiction: " <>
            (c.explanation || "conflict between #{c.node_a_type} and #{c.node_b_type}")

        metadata = %{
          "kind" => "coherence_finding",
          "contradiction_id" => c.id,
          "severity" => c.severity,
          "mode" => c.mode
        }

        {:ok, message} =
          %HydraX.Product.ProductMessage{}
          |> HydraX.Product.ProductMessage.changeset(%{
            "product_conversation_id" => conversation.id,
            "role" => "system",
            "content" => content,
            "metadata" => metadata
          })
          |> HydraX.Repo.insert()

        ProductPubSub.broadcast_project_event(c.project_id, "chat.message_inserted", %{
          conversation_id: conversation.id,
          message: message
        })

      _ ->
        :skip
    end
  end

  defp actor(opts) do
    cond do
      opts[:user_id] -> %{type: "user", id: to_string(opts[:user_id])}
      opts[:agent_id] -> %{type: "agent", id: opts[:agent_id]}
      true -> system_actor()
    end
  end

  defp system_actor, do: %{type: "system", id: nil}

  defp apply_status_filter(query, nil), do: query
  defp apply_status_filter(query, status) when is_binary(status),
    do: where(query, [c], c.status == ^status)

  defp apply_status_filter(query, statuses) when is_list(statuses),
    do: where(query, [c], c.status in ^statuses)

  defp apply_severity_floor(query, nil), do: query

  defp apply_severity_floor(query, "low"), do: query

  defp apply_severity_floor(query, "medium"),
    do: where(query, [c], c.severity in ["medium", "high"])

  defp apply_severity_floor(query, "high"),
    do: where(query, [c], c.severity == "high")

  defp to_int(v) when is_integer(v), do: v
  defp to_int(v) when is_binary(v), do: String.to_integer(v)
end
