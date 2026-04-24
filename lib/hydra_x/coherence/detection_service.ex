defmodule HydraX.Coherence.DetectionService do
  @moduledoc """
  Event-driven contradiction detection (spec `coherence-spec.md` §5).

  Cycle 2 minimum: Modes 1 (in-project) and 3 (principle-vs-practice).
  Modes 2 (cross-project) and 4 (intra-shared-memory) are scaffolded but
  opt-in — see `detect_for_new_node/3` dispatch.

  Detection is **best-effort and async**. Called from:
    * `Product.create_insight/create_decision/create_requirement/...`
    * `SharedMemory.create_node/...`
    * Manual user request via the Coherence chat

  The LLM call uses `HydraX.LLM.Router.complete/1` with a confidence
  threshold (defaults to medium). Sub-threshold findings are discarded.

  Runs inside a `Task.Supervisor` child so the originating request
  returns immediately.
  """

  require Logger

  alias HydraX.Coherence
  alias HydraX.LLM.Router, as: LLM
  alias HydraX.Product
  alias HydraX.Product.Graph
  alias HydraX.Repo
  alias HydraX.SharedMemory

  @confidence_rank %{"low" => 1, "medium" => 2, "high" => 3}
  @min_confidence "medium"
  @max_candidates 8
  @snippet_chars 600

  ## ------------------------------------------------------------------
  ## Public entry points
  ## ------------------------------------------------------------------

  @doc """
  Called right after a project-scope node is created or substantively
  edited. Spawns an async detection pass covering Modes 1, 2 and 3.
  """
  def on_project_node_change(project_id, node_type, node_id) do
    async(fn ->
      detect_in_project(project_id, node_type, node_id)
      detect_cross_project(project_id, node_type, node_id)
      detect_principle_vs_practice(project_id, node_type, node_id)
    end)
  end

  @doc """
  Called when a shared-memory node is created or edited. Runs the
  retroactive principle-vs-practice scan across the user's projects
  (spec §5) and the Mode 4 intra-shared-memory sweep within the
  changed node's scope.
  """
  def on_shared_memory_node_change(%SharedMemory.Node{} = shared_node) do
    async(fn ->
      detect_principle_retroactive(shared_node)
      detect_intra_shared_memory(shared_node)
    end)
  end

  ## ------------------------------------------------------------------
  ## Mode 1 — in-project
  ## ------------------------------------------------------------------

  def detect_in_project(project_id, node_type, node_id) do
    target = load_project_node(node_type, node_id)

    if is_nil(target),
      do: :skip,
      else: do_detect_in_project(project_id, target, node_type, node_id)
  end

  defp do_detect_in_project(project_id, target, node_type, node_id) do
    candidates = candidate_project_nodes(project_id, node_type, node_id)

    Enum.each(candidates, fn {other_type, other_id, other} ->
      case assess_pair(target, node_type, other, other_type, "in_project") do
        {:ok, verdict} ->
          maybe_record(verdict, %{
            project_id: project_id,
            mode: "in_project",
            node_a_type: to_string(node_type),
            node_a_id: node_id,
            node_a_scope: "project",
            node_b_type: to_string(other_type),
            node_b_id: other_id,
            node_b_scope: "project"
          })

        :skip ->
          :ok
      end
    end)
  end

  ## ------------------------------------------------------------------
  ## Mode 2 — cross-project
  ## ------------------------------------------------------------------

  @doc """
  Scan the changed project node against recent nodes of the same type in
  the *other* projects owned by the same user. "I said X in project A,
  and something that contradicts X in project B" is a failure mode the
  in-project pass can't catch.
  """
  def detect_cross_project(project_id, node_type, node_id) do
    target = load_project_node(node_type, node_id)

    if is_nil(target),
      do: :skip,
      else: do_detect_cross_project(project_id, target, node_type, node_id)
  end

  defp do_detect_cross_project(project_id, target, node_type, node_id) do
    project = Product.get_project!(project_id)
    shared_scope = resolve_shared_scope_for(project)

    if is_nil(shared_scope) do
      :skip
    else
      other_projects =
        shared_scope.owner_user_id
        |> list_owner_projects()
        |> Enum.reject(&(&1.id == project_id))

      Enum.each(other_projects, fn other_project ->
        case fetch_project_nodes(other_project.id, to_string(node_type)) do
          {:ok, records} ->
            records
            |> Enum.reject(&(&1.id == node_id))
            |> Enum.take(@max_candidates)
            |> Enum.each(fn record ->
              case assess_pair(target, node_type, record, node_type, "cross_project") do
                {:ok, verdict} ->
                  maybe_record(verdict, %{
                    project_id: project_id,
                    shared_scope_id: shared_scope.id,
                    mode: "cross_project",
                    node_a_type: to_string(node_type),
                    node_a_id: node_id,
                    node_a_scope: "project",
                    node_b_type: to_string(node_type),
                    node_b_id: record.id,
                    node_b_scope: "project",
                    context_diff: %{"peer_project_id" => other_project.id}
                  })

                :skip ->
                  :ok
              end
            end)

          _ ->
            :ok
        end
      end)
    end
  end

  ## ------------------------------------------------------------------
  ## Mode 3 — principle-vs-practice
  ## ------------------------------------------------------------------

  def detect_principle_vs_practice(project_id, node_type, node_id) do
    target = load_project_node(node_type, node_id)
    if is_nil(target), do: :skip, else: do_detect_pvp(project_id, target, node_type, node_id)
  end

  defp do_detect_pvp(project_id, target, node_type, node_id) do
    project = Product.get_project!(project_id)
    shared_scope = resolve_shared_scope_for(project)

    if is_nil(shared_scope) do
      :skip
    else
      shared_scope
      |> SharedMemory.list_nodes()
      |> Enum.take(@max_candidates)
      |> Enum.each(fn shared_node ->
        case assess_pair(target, node_type, shared_node, :shared, "principle_vs_practice") do
          {:ok, verdict} ->
            maybe_record(verdict, %{
              project_id: project_id,
              shared_scope_id: shared_node.shared_scope_id,
              mode: "principle_vs_practice",
              node_a_type: to_string(node_type),
              node_a_id: node_id,
              node_a_scope: "project",
              node_b_type: shared_node.node_type,
              node_b_id: shared_node.id,
              node_b_scope: "shared"
            })

          :skip ->
            :ok
        end
      end)
    end
  end

  defp detect_principle_retroactive(%SharedMemory.Node{} = shared_node) do
    # For every project whose owner owns this shared scope, scan existing
    # project nodes against the newly-added/edited shared node.
    shared_scope = Repo.get!(HydraX.Accounts.SharedScope, shared_node.shared_scope_id)
    owner_projects = list_owner_projects(shared_scope.owner_user_id)

    Enum.each(owner_projects, fn project ->
      Enum.each(["insight", "decision", "requirement", "strategy"], fn type ->
        {:ok, records} = fetch_project_nodes(project.id, type)

        Enum.take(records, @max_candidates)
        |> Enum.each(fn record ->
          case assess_pair(record, type, shared_node, :shared, "principle_vs_practice") do
            {:ok, verdict} ->
              maybe_record(verdict, %{
                project_id: project.id,
                shared_scope_id: shared_node.shared_scope_id,
                mode: "principle_vs_practice",
                node_a_type: to_string(type),
                node_a_id: record.id,
                node_a_scope: "project",
                node_b_type: shared_node.node_type,
                node_b_id: shared_node.id,
                node_b_scope: "shared"
              })

            :skip ->
              :ok
          end
        end)
      end)
    end)
  end

  ## ------------------------------------------------------------------
  ## Mode 4 — intra-shared-memory
  ## ------------------------------------------------------------------

  @doc """
  Pairwise scan of the changed shared-memory node against other nodes in
  the same shared scope. Two principles living side-by-side that contradict
  each other would slip past Mode 3 (which pairs shared × project) —
  Mode 4 catches them at source.
  """
  def detect_intra_shared_memory(%SharedMemory.Node{} = changed) do
    siblings =
      changed.shared_scope_id
      |> SharedMemory.list_nodes()
      |> Enum.reject(&(&1.id == changed.id))
      |> Enum.take(@max_candidates)

    Enum.each(siblings, fn other ->
      case assess_pair(changed, :shared, other, :shared, "intra_shared_memory") do
        {:ok, verdict} ->
          maybe_record(verdict, %{
            project_id: nil,
            shared_scope_id: changed.shared_scope_id,
            mode: "intra_shared_memory",
            node_a_type: changed.node_type,
            node_a_id: changed.id,
            node_a_scope: "shared",
            node_b_type: other.node_type,
            node_b_id: other.id,
            node_b_scope: "shared"
          })

        :skip ->
          :ok
      end
    end)
  end

  ## ------------------------------------------------------------------
  ## LLM assessment
  ## ------------------------------------------------------------------

  defp assess_pair(target, target_type, other, other_type, mode) do
    request = %{
      agent_id: nil,
      process_type: "coherence_detection",
      messages: [
        %{role: "system", content: system_prompt(mode)},
        %{role: "user", content: user_prompt(target, target_type, other, other_type)}
      ],
      max_tokens: 300,
      temperature: 0.2
    }

    case LLM.complete(request) do
      {:ok, %{content: content}} when is_binary(content) ->
        parse_assessment(content)

      {:ok, _} ->
        :skip

      {:error, _} ->
        :skip
    end
  rescue
    _ -> :skip
  end

  defp parse_assessment(content) do
    # Prompt format instructs the model to start with YES/NO + JSON.
    trimmed = String.trim(content)

    cond do
      String.starts_with?(trimmed, "NO") ->
        :skip

      String.starts_with?(trimmed, "YES") ->
        extracted = Regex.run(~r/\{.*\}/s, trimmed, capture: :first)

        case extracted do
          [json] ->
            case Jason.decode(json) do
              {:ok, %{"confidence" => conf, "explanation" => exp} = data} ->
                {:ok,
                 %{
                   confidence: normalise(conf, "medium", ["low", "medium", "high"]),
                   severity:
                     normalise(data["severity"] || "medium", "medium", ["low", "medium", "high"]),
                   explanation: exp,
                   suggested_resolutions: data["suggested_resolutions"] || []
                 }}

              {:ok, partial} ->
                Logger.info(
                  "[Coherence] YES without required fields, keys=#{inspect(Map.keys(partial))}"
                )

                {:ok,
                 %{
                   confidence: "medium",
                   severity: "medium",
                   explanation: trimmed,
                   suggested_resolutions: []
                 }}

              {:error, reason} ->
                Logger.info(
                  "[Coherence] YES with malformed JSON: #{inspect(reason)} — accepting with medium confidence"
                )

                {:ok,
                 %{
                   confidence: "medium",
                   severity: "medium",
                   explanation: trimmed,
                   suggested_resolutions: []
                 }}
            end

          nil ->
            # Response starts with YES but no braces — likely truncated.
            # Log so we can investigate prompt quality rather than silently dropping.
            Logger.warning(
              "[Coherence] truncated YES response (no JSON object): " <>
                String.slice(trimmed, 0, 200)
            )

            :skip
        end

      true ->
        # Response didn't start with YES or NO — prompt compliance failure.
        Logger.info(
          "[Coherence] non-compliant assessment (no YES/NO prefix): " <>
            String.slice(trimmed, 0, 100)
        )

        :skip
    end
  end

  defp maybe_record(verdict, base_attrs) do
    if Map.get(@confidence_rank, verdict.confidence, 0) <
         Map.get(@confidence_rank, @min_confidence, 2) do
      :below_threshold
    else
      Coherence.record_detection(
        Map.merge(base_attrs, %{
          "explanation" => verdict.explanation,
          "severity" => verdict.severity,
          "confidence" => verdict.confidence,
          "suggested_resolutions" => verdict.suggested_resolutions
        })
      )
    end
  end

  defp normalise(value, default, allowed) do
    v = value |> to_string() |> String.downcase()
    if v in allowed, do: v, else: default
  end

  ## ------------------------------------------------------------------
  ## Data fetch helpers
  ## ------------------------------------------------------------------

  defp load_project_node(node_type, node_id) do
    case Graph.resolve_node(to_string(node_type), to_int(node_id)) do
      {:ok, record} -> record
      _ -> nil
    end
  end

  defp candidate_project_nodes(project_id, node_type, node_id) do
    # Primitive-keyed: fetch any claim-extending substrate node plus
    # still-typed `vision` records. Spec §9 — contradiction detection
    # is domain-neutral and operates on the `claim` primitive.
    substrate_candidates(project_id, node_type, node_id) ++
      vision_candidates(project_id, node_type, node_id)
  end

  defp substrate_candidates(project_id, node_type, node_id) do
    import Ecto.Query

    from(n in HydraX.Graph.Node,
      where:
        n.project_id == ^project_id and n.extends_primitive == "claim" and
          is_nil(n.archived_at)
    )
    |> order_by([n], desc: n.updated_at)
    |> limit(^(@max_candidates * 2))
    |> Repo.all()
    |> Enum.reject(fn n ->
      to_string(n.type_key) == to_string(node_type) and n.id == to_int(node_id)
    end)
    |> Enum.take(@max_candidates)
    |> Enum.map(fn n -> {n.type_key, n.id, n} end)
  end

  defp vision_candidates(project_id, node_type, node_id) do
    import Ecto.Query

    HydraX.Product.Vision
    |> where([r], r.project_id == ^project_id)
    |> order_by([r], desc: r.updated_at)
    |> limit(^(@max_candidates * 2))
    |> Repo.all()
    |> Enum.reject(fn r ->
      to_string(node_type) == "vision" and r.id == to_int(node_id)
    end)
    |> Enum.take(@max_candidates)
    |> Enum.map(fn r -> {"vision", r.id, r} end)
  end

  defp fetch_project_nodes(project_id, type) do
    import Ecto.Query

    query =
      case type do
        "vision" ->
          HydraX.Product.Vision

        type_key ->
          from n in HydraX.Graph.Node, where: n.type_key == ^type_key
      end

    if query do
      records =
        query
        |> where([r], r.project_id == ^project_id)
        |> order_by([r], desc: r.updated_at)
        |> limit(^(@max_candidates * 2))
        |> Repo.all()

      {:ok, records}
    else
      {:ok, []}
    end
  end

  defp resolve_shared_scope_for(project) do
    # Project → workspace → owner user → shared scope. Falls back to
    # nil if the workspace/owner isn't resolvable yet (Cycle 1 mode).
    cond do
      is_nil(project.workspace_id) ->
        nil

      true ->
        workspace = Repo.get(HydraX.Accounts.Workspace, project.workspace_id)

        if workspace && workspace.created_by_user_id do
          HydraX.Accounts.SharedScope
          |> Repo.get_by(owner_user_id: workspace.created_by_user_id)
        end
    end
  end

  defp list_owner_projects(owner_user_id) do
    import Ecto.Query

    from(p in HydraX.Product.Project,
      join: w in HydraX.Accounts.Workspace,
      on: w.id == p.workspace_id,
      where: w.created_by_user_id == ^owner_user_id
    )
    |> Repo.all()
  end

  defp async(fun) do
    case Process.whereis(HydraX.TaskSupervisor) do
      nil ->
        # Task supervisor not running (tests that bypass app supervisor);
        # run inline.
        fun.()

      _pid ->
        Task.Supervisor.start_child(HydraX.TaskSupervisor, fn ->
          try do
            fun.()
          rescue
            err ->
              Logger.warning("[Coherence] detection raised: #{inspect(err)}")
          end
        end)
    end
  end

  ## ------------------------------------------------------------------
  ## Prompt construction
  ## ------------------------------------------------------------------

  defp system_prompt("principle_vs_practice"), do: base_system_prompt("principle-vs-practice")
  defp system_prompt("intra_shared_memory"), do: base_system_prompt("intra-shared-memory")
  defp system_prompt("cross_project"), do: base_system_prompt("cross-project")
  defp system_prompt(_), do: base_system_prompt("in-project")

  defp base_system_prompt(kind) do
    """
    You are Coherence, a service agent in Hydra that watches for
    contradictions in a user's typed knowledge graph.

    You will be shown two nodes from a "#{kind}" scan. Decide: do these
    imply opposing actions, beliefs, or commitments? Similarity of topic
    is NOT enough — look for genuine tension, where one node's truth
    undermines the other's.

    Respond on the first line with exactly "YES" or "NO".

    If YES, follow with a single-line JSON object with these keys:
      confidence: "low" | "medium" | "high"
      severity: "low" | "medium" | "high"
      explanation: string — 1–3 sentences citing the specific tension
      suggested_resolutions: array of short strings (2–5 suggestions)

    If NO, stop after "NO" — do not add JSON.

    Avoid false positives. When unsure, respond "NO".
    """
  end

  defp user_prompt(target, target_type, other, other_type) do
    """
    TARGET (#{target_type}):
    Title: #{field(target, :title) || "(untitled)"}
    Body: #{excerpt(target)}

    CANDIDATE (#{other_type}):
    Title: #{field(other, :title) || "(untitled)"}
    Body: #{excerpt(other)}

    Do the target and the candidate contradict?
    """
  end

  defp field(struct, key) when is_struct(struct), do: Map.get(struct, key)
  defp field(_, _), do: nil

  defp excerpt(struct) do
    raw =
      Map.get(struct, :body) || Map.get(struct, :content) || Map.get(struct, :description) || ""

    String.slice(to_string(raw), 0, @snippet_chars)
  end

  defp to_int(v) when is_integer(v), do: v
  defp to_int(v) when is_binary(v), do: String.to_integer(v)
end
