defmodule HydraX.Product do
  @moduledoc """
  Product-domain data and provisioning helpers built inside the Hydra-X repo.
  """

  import Ecto.Query

  alias HydraX.Accounts
  alias HydraX.Config
  alias HydraX.Embeddings
  alias HydraX.Ingest.Parser
  alias HydraX.Memory
  alias HydraX.Product.ArtifactVersion
  alias HydraX.Product.BoardEdge
  alias HydraX.Product.BoardNode
  alias HydraX.Product.BoardSession
  alias HydraX.Product.Citations
  alias HydraX.Product.GraphFlag
  alias HydraX.Graph.Node, as: GraphNode
  alias HydraX.Graph.Nodes, as: GraphNodes
  alias HydraX.Product.InsightEvidence
  alias HydraX.Product.Onboarding
  alias HydraX.Product.Project
  alias HydraX.Product.ProductConversation
  alias HydraX.Product.ProductMessage
  alias HydraX.Product.PubSub, as: ProductPubSub
  alias HydraX.Product.RequirementInsight
  alias HydraX.Product.RoutineRun
  alias HydraX.Product.SourceChunk
  alias HydraX.Product.TaskFeedback
  alias HydraX.Product.WorkspaceScaffold
  alias HydraX.PretrainedProjects.ProductDevelopment
  alias HydraX.Repo
  alias HydraX.Runtime
  alias HydraX.Runtime.AgentProfile
  alias HydraX.Runtime.Conversation

  @chunk_size_words 120
  @chunk_overlap_words 30
  @default_search_limit 5
  @source_search_tool HydraX.Product.Tools.SourceSearch
  @library_query_tool HydraX.Product.Tools.LibraryQuery
  @library_gaps_tool HydraX.Product.Tools.LibraryGaps
  @insight_create_tool HydraX.Product.Tools.InsightCreate
  @insight_update_tool HydraX.Product.Tools.InsightUpdate
  @requirement_create_tool HydraX.Product.Tools.RequirementCreate
  @architecture_create_tool HydraX.Product.Tools.ArchitectureCreate
  @architecture_update_tool HydraX.Product.Tools.ArchitectureUpdate
  @feasibility_assess_tool HydraX.Product.Tools.FeasibilityAssess
  @design_create_tool HydraX.Product.Tools.DesignCreate
  @design_update_tool HydraX.Product.Tools.DesignUpdate
  @pattern_check_tool HydraX.Product.Tools.PatternCheck
  @graph_query_tool HydraX.Product.Tools.GraphQuery
  @trail_trace_tool HydraX.Product.Tools.TrailTrace
  @decision_create_tool HydraX.Product.Tools.DecisionCreate
  @strategy_create_tool HydraX.Product.Tools.StrategyCreate
  @artifact_create_tool HydraX.Product.Tools.ArtifactCreate
  @artifact_update_tool HydraX.Product.Tools.ArtifactUpdate
  @simulation_propose_tool HydraX.Product.Tools.SimulationPropose
  @knowledge_propose_tool HydraX.Product.Tools.KnowledgePropose
  @knowledge_update_tool HydraX.Product.Tools.KnowledgeUpdate
  @project_context_update_tool HydraX.Product.Tools.ProjectContextUpdate

  @code_read_tool HydraX.Product.Tools.CodeRead
  @code_write_tool HydraX.Product.Tools.CodeWrite
  @code_edit_tool HydraX.Product.Tools.CodeEdit
  @code_list_tool HydraX.Product.Tools.CodeList
  @code_search_tool HydraX.Product.Tools.CodeSearch
  @code_exec_tool HydraX.Product.Tools.CodeExec
  @code_test_tool HydraX.Product.Tools.CodeTest

  @agent_preloads [
    :researcher_agent,
    :strategist_agent,
    :architect_agent,
    :designer_agent,
    :memory_agent,
    :coder_agent
  ]

  def list_projects(opts \\ []) do
    status = Keyword.get(opts, :status)
    search = Keyword.get(opts, :search)

    Project
    |> maybe_filter_project_status(status)
    |> maybe_filter_project_search(search)
    |> preload(^@agent_preloads)
    |> order_by([project], asc: project.name)
    |> Repo.all()
  end

  def get_project!(id) do
    Project
    |> preload(^@agent_preloads)
    |> Repo.get!(id)
  end

  @doc """
  Mark the project's onboarding fork screen as past. Idempotent — safe
  to call from any of the four scenario flows or from the skip path.
  """
  def mark_first_session_completed(%Project{has_completed_first_session: true} = project),
    do: {:ok, project}

  def mark_first_session_completed(%Project{} = project) do
    project
    |> Project.changeset(%{"has_completed_first_session" => true})
    |> Repo.update()
  end

  def project_counts(project_or_id) do
    project_id = project_id(project_or_id)

    %{
      sources: count_type_key_nodes(project_id, "source", :all),
      insights: count_insight_nodes(project_id),
      requirements: count_type_key_nodes(project_id, "requirement", :all),
      conversations: count_project_records(ProductConversation, project_id),
      decisions: count_type_key_nodes(project_id, "decision", :all),
      strategies: count_type_key_nodes(project_id, "strategy", :all),
      design_nodes: count_type_key_nodes(project_id, "design_node"),
      architecture_nodes: count_type_key_nodes(project_id, "architecture_node"),
      tasks: count_type_key_nodes(project_id, "task", :all),
      learnings: count_type_key_nodes(project_id, "learning", :all),
      flags:
        GraphFlag
        |> where([f], f.project_id == ^project_id and f.status == "open")
        |> Repo.aggregate(:count, :id)
    }
  end

  def change_project(project \\ %Project{}, attrs \\ %{}) do
    Project.changeset(project, normalize_project_attrs(attrs))
  end

  def create_project(attrs) when is_map(attrs) do
    create_project_record(attrs)
  end

  def create_project_with_onboarding(attrs) when is_map(attrs) do
    case create_project_record(attrs) do
      {:ok, project} ->
        onboarding =
          case Onboarding.setup_project!(project) do
            {:ok, %{session_id: sid, conversation_id: cid}} ->
              %{onboarding_session_id: sid, onboarding_conversation_id: cid}

            _ ->
              %{}
          end

        {:ok, project, onboarding}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp create_project_record(attrs) when is_map(attrs) do
    attrs =
      attrs
      |> normalize_project_attrs()
      |> put_default_workspace_id()

    Repo.transaction(fn ->
      researcher = provision_agent!(attrs, "researcher")
      strategist = provision_agent!(attrs, "strategist")
      architect = provision_agent!(attrs, "architect")
      designer = provision_agent!(attrs, "designer")
      memory_agent = provision_agent!(attrs, "memory_agent")

      project_attrs =
        attrs
        |> Map.put("researcher_agent_id", researcher.id)
        |> Map.put("strategist_agent_id", strategist.id)
        |> Map.put("architect_agent_id", architect.id)
        |> Map.put("designer_agent_id", designer.id)
        |> Map.put("memory_agent_id", memory_agent.id)

      %Project{}
      |> Project.changeset(project_attrs)
      |> Repo.insert()
      |> case do
        {:ok, project} ->
          :ok = ProductDevelopment.apply_to_project(project.id)
          provision_default_artifacts!(project)
          maybe_start_initiative_engine(project)
          Repo.preload(project, @agent_preloads)

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  defp put_default_workspace_id(%{"workspace_id" => workspace_id} = attrs)
       when is_binary(workspace_id) and workspace_id != "" do
    attrs
  end

  defp put_default_workspace_id(%{"workspace_id" => workspace_id} = attrs)
       when not is_nil(workspace_id) do
    attrs
  end

  defp put_default_workspace_id(attrs) do
    Map.put(attrs, "workspace_id", Accounts.default_workspace_id())
  end

  def update_project(%Project{} = project, attrs) do
    attrs =
      attrs
      |> HydraX.Runtime.Helpers.normalize_string_keys()
      |> Map.put_new("name", project.name)
      |> Map.put_new("slug", project.slug)
      |> Map.put_new("description", project.description)
      |> Map.put_new("status", project.status)
      |> Map.put_new("metadata", project.metadata || %{})

    project
    |> Project.changeset(normalize_project_attrs(attrs))
    |> Repo.update()
    |> case do
      {:ok, updated} ->
        updated = Repo.preload(updated, @agent_preloads)
        ProductPubSub.broadcast_project_event(updated.id, "project.updated", updated)
        {:ok, updated}

      error ->
        error
    end
  end

  def delete_project(%Project{} = project) do
    project = Repo.preload(project, @agent_preloads)

    case Repo.delete(project) do
      {:ok, deleted} ->
        ProductPubSub.broadcast_project_event(deleted.id, "project.deleted", project)
        {:ok, deleted}

      error ->
        error
    end
  end

  def list_sources(project_or_id, opts \\ []) do
    project_id = project_id(project_or_id)
    processing_status = Keyword.get(opts, :processing_status)
    source_type = Keyword.get(opts, :source_type)
    search = Keyword.get(opts, :search)

    from(n in GraphNode,
      where: n.project_id == ^project_id and n.type_key == "source"
    )
    |> maybe_filter_source_processing_status(processing_status)
    |> maybe_filter_source_type(source_type)
    |> maybe_filter_source_search(search)
    |> preload([:source_chunks])
    |> order_by([source], desc: source.inserted_at)
    |> Repo.all()
    |> Enum.map(&hydrate_source_compat/1)
  end

  def get_source!(id) do
    from(n in GraphNode, where: n.id == ^id and n.type_key == "source")
    |> preload([:source_chunks])
    |> Repo.one!()
    |> hydrate_source_compat()
  end

  def get_project_source!(project_or_id, id) do
    project_id = project_id(project_or_id)

    from(n in GraphNode,
      where: n.project_id == ^project_id and n.id == ^id and n.type_key == "source"
    )
    |> preload([:source_chunks])
    |> Repo.one!()
    |> hydrate_source_compat()
  end

  def change_source(source \\ %GraphNode{type_key: "source"}, attrs \\ %{}) do
    GraphNode.changeset(source, source_node_attrs(source, normalize_source_attrs(attrs)))
  end

  def delete_source(%GraphNode{type_key: "source"} = source) do
    case Repo.delete(source) do
      {:ok, deleted} ->
        ProductPubSub.broadcast_project_event(deleted.project_id, "source.deleted", deleted)
        ProductPubSub.broadcast_source_event(deleted.id, "deleted", %{source: deleted})
        {:ok, deleted}

      error ->
        error
    end
  end

  def create_source(project_or_id, attrs) when is_map(attrs) do
    project = load_project(project_or_id)
    attrs = normalize_source_attrs(attrs)

    with {:ok, parsed} <- parse_source_payload(attrs) do
      # Assemble attribute map for substrate storage.
      source_attrs =
        attrs
        |> Map.drop(["upload"])
        |> Map.put("source_type", parsed.source_type)
        |> Map.put("content", parsed.content)
        |> Map.put("processing_status", "processing")
        |> Map.put("metadata", parsed.metadata)

      node_attrs = %{
        type_key: "source",
        title: source_attrs["title"],
        body: source_attrs["content"],
        status: source_attrs["processing_status"],
        attributes: source_attributes(source_attrs)
      }

      with {:ok, source} <- GraphNodes.create_node(project.id, node_attrs) do
        ProductPubSub.broadcast_project_event(project.id, "source.created", source)

        ProductPubSub.broadcast_source_progress(source, "progress", %{
          stage: "chunking"
        })

        source
        |> persist_source_chunks(parsed, project.id)
        |> case do
          {:ok, completed_source} ->
            completed_source =
              maybe_mirror_source_memories(completed_source, project, attrs)

            ProductPubSub.broadcast_project_event(project.id, "source.updated", completed_source)

            ProductPubSub.broadcast_source_progress(completed_source, "completed", %{
              stage: "completed",
              chunk_count: length(completed_source.source_chunks || [])
            })

            {:ok, hydrate_source_compat(completed_source)}

          {:error, %Ecto.Changeset{} = changeset} ->
            failed_source = mark_source_failed(source)

            ProductPubSub.broadcast_project_event(project.id, "source.updated", failed_source)

            ProductPubSub.broadcast_source_progress(failed_source, "failed", %{
              stage: "failed",
              error: "source ingestion failed"
            })

            {:error, changeset}

          {:error, reason} ->
            failed_source = mark_source_failed(source)

            ProductPubSub.broadcast_project_event(project.id, "source.updated", failed_source)

            ProductPubSub.broadcast_source_progress(failed_source, "failed", %{
              stage: "failed",
              error: source_error_message(reason)
            })

            {:error, source_error_changeset(project, attrs, reason)}
        end
      end
    else
      {:error, reason} ->
        {:error, source_error_changeset(project, attrs, reason)}
    end
  end

  def search_source_chunks(project_or_id, query, opts \\ []) do
    project_id = project_id(project_or_id)
    limit = Keyword.get(opts, :limit, @default_search_limit)
    candidate_limit = max(limit * 10, 40)
    query = String.trim(to_string(query || ""))

    if query == "" do
      []
    else
      query_context = source_query_context(query)

      project_id
      |> source_search_candidates(query, candidate_limit)
      |> Enum.map(&score_source_chunk(&1, query_context))
      |> Enum.filter(&(&1.score > 0))
      |> Enum.sort_by(fn ranked ->
        {-ranked.score, -(ranked.lexical_score || 0), -ranked.chunk.id}
      end)
      |> Enum.take(limit)
    end
  end

  def list_insights(project_or_id, opts \\ []) do
    project_id = project_id(project_or_id)
    status = Keyword.get(opts, :status)
    search = Keyword.get(opts, :search)

    query =
      from(n in GraphNode,
        where: n.project_id == ^project_id and n.type_key == "insight" and is_nil(n.archived_at)
      )

    query
    |> maybe_filter_insight_status(status)
    |> maybe_filter_insight_search(search)
    |> preload(^insight_preloads())
    |> order_by([n], desc: n.updated_at)
    |> Repo.all()
  end

  def get_project_insight!(project_or_id, insight_id) do
    project_id = project_id(project_or_id)

    from(n in GraphNode,
      where:
        n.project_id == ^project_id and
          n.id == ^parse_integer(insight_id) and
          n.type_key == "insight"
    )
    |> preload(^insight_preloads())
    |> Repo.one!()
  end

  def create_insight(project_or_id, attrs) when is_map(attrs) do
    project = load_project(project_or_id)
    attrs = normalize_product_record_attrs(attrs)
    evidence_chunk_ids = normalize_integer_list(attrs["evidence_chunk_ids"])

    if evidence_chunk_ids == [] do
      {:error,
       insight_error_changeset(
         project.id,
         attrs,
         "evidence_chunk_ids",
         "must include at least one source chunk"
       )}
    else
      case load_project_chunks(project.id, evidence_chunk_ids) do
        {:ok, chunks} ->
          Repo.transaction(fn ->
            node_attrs = %{
              type_key: "insight",
              title: attrs["title"],
              body: attrs["body"],
              status: attrs["status"] || "draft",
              attributes:
                Map.put(attrs["metadata"] || %{}, "evidence_chunk_ids", evidence_chunk_ids)
            }

            insight =
              case GraphNodes.create_node(project.id, node_attrs) do
                {:ok, node} -> node
                {:error, changeset} -> Repo.rollback(changeset)
              end

            persist_insight_evidence!(insight, chunks, attrs["evidence_quotes"] || %{})
            Repo.preload(insight, insight_preloads())
          end)
          |> unwrap_transaction()
          |> maybe_broadcast_project_record("insight.created")

        {:error, reason} ->
          {:error, insight_error_changeset(project.id, attrs, "evidence_chunk_ids", reason)}
      end
    end
  end

  def delete_insight(%GraphNode{type_key: "insight"} = insight) do
    insight
    |> Repo.delete()
    |> maybe_broadcast_project_record("insight.deleted")
    |> maybe_notify_propagation("insight", :deleted)
  end

  def update_insight(%GraphNode{type_key: "insight"} = insight, attrs) when is_map(attrs) do
    attrs = normalize_product_record_attrs(attrs)
    evidence_chunk_ids = normalize_integer_list(Map.get(attrs, "evidence_chunk_ids"))

    existing_chunk_ids =
      case insight.insight_evidence do
        %Ecto.Association.NotLoaded{} -> insight_evidence_chunk_ids(insight.id)
        list when is_list(list) -> Enum.map(list, & &1.source_chunk_id)
        _ -> []
      end

    desired_chunk_ids =
      if Map.has_key?(attrs, "evidence_chunk_ids"),
        do: evidence_chunk_ids,
        else: existing_chunk_ids

    if desired_chunk_ids == [] do
      {:error,
       insight_error_changeset(
         insight.project_id,
         attrs,
         "evidence_chunk_ids",
         "must include at least one source chunk"
       )}
    else
      case load_project_chunks(insight.project_id, desired_chunk_ids) do
        {:ok, chunks} ->
          Repo.transaction(fn ->
            merged_attributes =
              (insight.attributes || %{})
              |> Map.merge(attrs["metadata"] || %{})
              |> Map.put("evidence_chunk_ids", desired_chunk_ids)

            node_attrs = %{
              title: attrs["title"] || insight.title,
              body: attrs["body"] || insight.body,
              status: attrs["status"] || insight.status,
              attributes: merged_attributes
            }

            updated =
              case GraphNodes.update_node(insight, node_attrs) do
                {:ok, n} -> n
                {:error, changeset} -> Repo.rollback(changeset)
              end

            if Map.has_key?(attrs, "evidence_chunk_ids") do
              delete_insight_evidence!(updated.id)
              persist_insight_evidence!(updated, chunks, attrs["evidence_quotes"] || %{})
            end

            Repo.preload(updated, insight_preloads())
          end)
          |> unwrap_transaction()
          |> maybe_broadcast_project_record("insight.updated")
          |> maybe_notify_propagation("insight", :updated)

        {:error, reason} ->
          {:error,
           insight_error_changeset(insight.project_id, attrs, "evidence_chunk_ids", reason)}
      end
    end
  end

  defp insight_evidence_chunk_ids(insight_id) do
    Repo.all(
      from e in InsightEvidence,
        where: e.insight_id == ^insight_id,
        select: e.source_chunk_id
    )
  end

  defp maybe_filter_insight_status(query, nil), do: query
  defp maybe_filter_insight_status(query, ""), do: query
  defp maybe_filter_insight_status(query, status), do: where(query, [n], n.status == ^status)

  def list_requirements(project_or_id, opts \\ []) do
    project_id = project_id(project_or_id)
    status = Keyword.get(opts, :status)
    grounded = Keyword.get(opts, :grounded)
    search = Keyword.get(opts, :search)

    from(n in GraphNode,
      where: n.project_id == ^project_id and n.type_key == "requirement" and is_nil(n.archived_at)
    )
    |> maybe_filter_product_record_status(status)
    |> maybe_filter_requirement_grounded(grounded)
    |> maybe_filter_requirement_search(search)
    |> preload(^requirement_preloads())
    |> order_by([r], desc: r.updated_at)
    |> Repo.all()
    |> Enum.map(&hydrate_requirement_compat/1)
  end

  def get_project_requirement!(project_or_id, requirement_id) do
    project_id = project_id(project_or_id)

    from(n in GraphNode,
      where:
        n.project_id == ^project_id and n.id == ^parse_integer(requirement_id) and
          n.type_key == "requirement"
    )
    |> preload(^requirement_preloads())
    |> Repo.one!()
    |> hydrate_requirement_compat()
  end

  def create_requirement(project_or_id, attrs) when is_map(attrs) do
    project = load_project(project_or_id)
    attrs = normalize_product_record_attrs(attrs)
    insight_ids = normalize_integer_list(attrs["insight_ids"])

    case load_project_insights(project.id, insight_ids) do
      {:ok, insights} ->
        grounded = grounded_requirement?(insights)
        status = attrs["status"] || "draft"

        if status == "accepted" and not grounded do
          {:error,
           requirement_error_changeset(
             project.id,
             attrs,
             "status",
             "cannot accept an ungrounded requirement"
           )}
        else
          Repo.transaction(fn ->
            node_attrs = %{
              type_key: "requirement",
              title: attrs["title"],
              body: attrs["body"],
              status: status,
              attributes:
                (attrs["metadata"] || %{})
                |> Map.put("grounded", grounded)
                |> Map.put("insight_ids", insight_ids)
            }

            requirement =
              case GraphNodes.create_node(project.id, node_attrs) do
                {:ok, node} -> node
                {:error, changeset} -> Repo.rollback(changeset)
              end

            persist_requirement_insights!(requirement, insights)

            requirement
            |> Repo.preload(requirement_preloads())
            |> hydrate_requirement_compat()
          end)
          |> unwrap_transaction()
          |> maybe_broadcast_project_record("requirement.created")
        end

      {:error, reason} ->
        {:error, requirement_error_changeset(project.id, attrs, "insight_ids", reason)}
    end
  end

  def update_requirement(%GraphNode{type_key: "requirement"} = requirement, attrs)
      when is_map(attrs) do
    attrs = normalize_product_record_attrs(attrs)

    existing_insight_ids =
      case requirement.linked_requirement_insights do
        %Ecto.Association.NotLoaded{} -> linked_insight_ids(requirement.id)
        list when is_list(list) -> Enum.map(list, & &1.insight_id)
        _ -> []
      end

    insight_ids =
      if Map.has_key?(attrs, "insight_ids"),
        do: normalize_integer_list(attrs["insight_ids"]),
        else: existing_insight_ids

    case load_project_insights(requirement.project_id, insight_ids) do
      {:ok, insights} ->
        grounded = grounded_requirement?(insights)
        status = attrs["status"] || requirement.status

        if status == "accepted" and not grounded do
          {:error,
           requirement_error_changeset(
             requirement.project_id,
             attrs,
             "status",
             "cannot accept an ungrounded requirement"
           )}
        else
          Repo.transaction(fn ->
            merged_attributes =
              (requirement.attributes || %{})
              |> Map.merge(attrs["metadata"] || %{})
              |> Map.put("grounded", grounded)
              |> Map.put("insight_ids", insight_ids)

            node_attrs = %{
              title: attrs["title"] || requirement.title,
              body: attrs["body"] || requirement.body,
              status: status,
              attributes: merged_attributes
            }

            updated =
              case GraphNodes.update_node(requirement, node_attrs) do
                {:ok, n} -> n
                {:error, changeset} -> Repo.rollback(changeset)
              end

            if Map.has_key?(attrs, "insight_ids") do
              delete_requirement_insights!(updated.id)
              persist_requirement_insights!(updated, insights)
            end

            updated
            |> Repo.preload(requirement_preloads())
            |> hydrate_requirement_compat()
          end)
          |> unwrap_transaction()
          |> maybe_broadcast_project_record("requirement.updated")
          |> maybe_notify_propagation("requirement", :updated)
        end

      {:error, reason} ->
        {:error,
         requirement_error_changeset(requirement.project_id, attrs, "insight_ids", reason)}
    end
  end

  def delete_requirement(%GraphNode{type_key: "requirement"} = requirement) do
    requirement
    |> Repo.delete()
    |> maybe_broadcast_project_record("requirement.deleted")
    |> maybe_notify_propagation("requirement", :deleted)
  end

  defp linked_insight_ids(requirement_id) do
    Repo.all(
      from ri in RequirementInsight,
        where: ri.requirement_id == ^requirement_id,
        select: ri.insight_id
    )
  end

  defp hydrate_requirement_compat(%GraphNode{type_key: "requirement"} = requirement) do
    links = associated_list(requirement.linked_requirement_insights)

    %{
      requirement
      | grounded: Map.get(requirement.attributes || %{}, "grounded", false),
        requirement_insights: links
    }
  end

  defp hydrate_requirement_compat(requirement), do: requirement

  # -------------------------------------------------------------------
  # Decisions
  # -------------------------------------------------------------------

  def list_decisions(project_or_id, opts \\ []) do
    project_id = project_id(project_or_id)
    status = Keyword.get(opts, :status)
    search = Keyword.get(opts, :search)

    from(n in GraphNode,
      where: n.project_id == ^project_id and n.type_key == "decision" and is_nil(n.archived_at)
    )
    |> maybe_filter_product_record_status(status)
    |> maybe_filter_title_body_search(search)
    |> order_by([d], desc: d.updated_at)
    |> Repo.all()
  end

  def get_decision!(id) do
    Repo.one!(from n in GraphNode, where: n.id == ^id and n.type_key == "decision")
  end

  def get_project_decision!(project_or_id, id) do
    project_id = project_id(project_or_id)

    Repo.one!(
      from n in GraphNode,
        where:
          n.project_id == ^project_id and n.id == ^parse_integer(id) and
            n.type_key == "decision"
    )
  end

  def create_decision(project_or_id, attrs) when is_map(attrs) do
    project_id = project_id(project_or_id)
    attrs = normalize_product_record_attrs(attrs)

    node_attrs = %{
      type_key: "decision",
      title: attrs["title"],
      body: attrs["body"],
      status: attrs["status"] || "active",
      attributes: decision_attributes(attrs)
    }

    GraphNodes.create_node(project_id, node_attrs)
    |> maybe_broadcast_project_record("decision.created")
    |> maybe_notify_coherence("decision", :created)
  end

  def update_decision(%GraphNode{type_key: "decision"} = decision, attrs) when is_map(attrs) do
    attrs = normalize_product_record_attrs(attrs)

    merged_attributes =
      (decision.attributes || %{})
      |> Map.merge(attrs["metadata"] || %{})
      |> Map.merge(decision_attributes(attrs))

    node_attrs = %{
      title: attrs["title"] || decision.title,
      body: attrs["body"] || decision.body,
      status: attrs["status"] || decision.status,
      attributes: merged_attributes
    }

    GraphNodes.update_node(decision, node_attrs)
    |> maybe_broadcast_project_record("decision.updated")
    |> maybe_notify_propagation("decision", :updated)
  end

  def delete_decision(%GraphNode{type_key: "decision"} = decision) do
    decision
    |> Repo.delete()
    |> maybe_broadcast_project_record("decision.deleted")
    |> maybe_notify_propagation("decision", :deleted)
  end

  defp decision_attributes(attrs) do
    base = attrs["metadata"] || %{}

    Enum.reduce(
      [
        {"alternatives_considered", attrs["alternatives_considered"]},
        {"decided_by", attrs["decided_by"]},
        {"decided_at", attrs["decided_at"]},
        {"rationale", attrs["rationale"]},
        {"reversibility", attrs["reversibility"]}
      ],
      base,
      fn {k, v}, acc -> if is_nil(v), do: acc, else: Map.put(acc, k, v) end
    )
  end

  # -------------------------------------------------------------------
  # Strategies
  # -------------------------------------------------------------------

  def list_strategies(project_or_id, opts \\ []) do
    project_id = project_id(project_or_id)
    status = Keyword.get(opts, :status)
    search = Keyword.get(opts, :search)

    from(n in GraphNode,
      where: n.project_id == ^project_id and n.type_key == "strategy" and is_nil(n.archived_at)
    )
    |> maybe_filter_product_record_status(status)
    |> maybe_filter_title_body_search(search)
    |> order_by([s], desc: s.updated_at)
    |> Repo.all()
  end

  def get_strategy!(id) do
    Repo.one!(from n in GraphNode, where: n.id == ^id and n.type_key == "strategy")
  end

  def get_project_strategy!(project_or_id, id) do
    project_id = project_id(project_or_id)

    Repo.one!(
      from n in GraphNode,
        where:
          n.project_id == ^project_id and n.id == ^parse_integer(id) and
            n.type_key == "strategy"
    )
  end

  def create_strategy(project_or_id, attrs) when is_map(attrs) do
    project_id = project_id(project_or_id)
    attrs = normalize_product_record_attrs(attrs)

    node_attrs = %{
      type_key: "strategy",
      title: attrs["title"],
      body: attrs["body"],
      status: attrs["status"] || "active",
      attributes: attrs["metadata"] || %{}
    }

    GraphNodes.create_node(project_id, node_attrs)
    |> maybe_broadcast_project_record("strategy.created")
    |> maybe_notify_coherence("strategy", :created)
  end

  def update_strategy(%GraphNode{type_key: "strategy"} = strategy, attrs) when is_map(attrs) do
    attrs = normalize_product_record_attrs(attrs)

    merged_attributes = Map.merge(strategy.attributes || %{}, attrs["metadata"] || %{})

    GraphNodes.update_node(strategy, %{
      title: attrs["title"] || strategy.title,
      body: attrs["body"] || strategy.body,
      status: attrs["status"] || strategy.status,
      attributes: merged_attributes
    })
    |> maybe_broadcast_project_record("strategy.updated")
    |> maybe_notify_propagation("strategy", :updated)
  end

  def delete_strategy(%GraphNode{type_key: "strategy"} = strategy) do
    strategy
    |> Repo.delete()
    |> maybe_broadcast_project_record("strategy.deleted")
    |> maybe_notify_propagation("strategy", :deleted)
  end

  # -------------------------------------------------------------------
  # Design Nodes
  # -------------------------------------------------------------------

  def list_design_nodes(project_or_id, opts \\ []) do
    list_node_typed(project_or_id, "design_node", opts)
  end

  def get_design_node!(id), do: get_node_typed!(id, "design_node")

  def get_project_design_node!(project_or_id, id),
    do: get_project_node_typed!(project_or_id, id, "design_node")

  def create_design_node(project_or_id, attrs),
    do: create_node_typed(project_or_id, "design_node", attrs, "design_node.created")

  def update_design_node(%GraphNode{type_key: "design_node"} = node, attrs),
    do: update_node_typed(node, attrs, "design_node.updated", propagate: "design_node")

  def delete_design_node(%GraphNode{type_key: "design_node"} = node),
    do: delete_node_typed(node, "design_node.deleted", propagate: "design_node")

  # -------------------------------------------------------------------
  # Architecture Nodes
  # -------------------------------------------------------------------

  def list_architecture_nodes(project_or_id, opts \\ []) do
    list_node_typed(project_or_id, "architecture_node", opts)
  end

  def get_architecture_node!(id), do: get_node_typed!(id, "architecture_node")

  def get_project_architecture_node!(project_or_id, id),
    do: get_project_node_typed!(project_or_id, id, "architecture_node")

  def create_architecture_node(project_or_id, attrs),
    do: create_node_typed(project_or_id, "architecture_node", attrs, "architecture_node.created")

  def update_architecture_node(%GraphNode{type_key: "architecture_node"} = node, attrs),
    do:
      update_node_typed(node, attrs, "architecture_node.updated", propagate: "architecture_node")

  def delete_architecture_node(%GraphNode{type_key: "architecture_node"} = node),
    do: delete_node_typed(node, "architecture_node.deleted", propagate: "architecture_node")

  # Shared helpers for simple substrate-backed node types.
  # Domain-specific discriminators (design_node's `node_type`) live in
  # `attributes` — callers pass them through `attrs["node_type"]`.

  defp list_node_typed(project_or_id, type_key, opts) do
    project_id = project_id(project_or_id)
    status = Keyword.get(opts, :status)
    node_type = Keyword.get(opts, :node_type)
    search = Keyword.get(opts, :search)

    from(n in GraphNode,
      where: n.project_id == ^project_id and n.type_key == ^type_key and is_nil(n.archived_at)
    )
    |> maybe_filter_product_record_status(status)
    |> maybe_filter_node_type_attribute(node_type)
    |> maybe_filter_title_body_search(search)
    |> order_by([n], desc: n.updated_at)
    |> Repo.all()
  end

  defp get_node_typed!(id, type_key) do
    Repo.one!(from n in GraphNode, where: n.id == ^id and n.type_key == ^type_key)
  end

  defp get_project_node_typed!(project_or_id, id, type_key) do
    project_id = project_id(project_or_id)

    Repo.one!(
      from n in GraphNode,
        where:
          n.project_id == ^project_id and n.id == ^parse_integer(id) and
            n.type_key == ^type_key
    )
  end

  defp create_node_typed(project_or_id, type_key, attrs, event) do
    project_id = project_id(project_or_id)
    attrs = normalize_product_record_attrs(attrs)

    merged_attributes =
      case attrs["node_type"] do
        nil -> attrs["metadata"] || %{}
        nt -> Map.put(attrs["metadata"] || %{}, "node_type", nt)
      end

    node_attrs = %{
      type_key: type_key,
      title: attrs["title"],
      body: attrs["body"],
      status: attrs["status"] || "active",
      attributes: merged_attributes
    }

    GraphNodes.create_node(project_id, node_attrs)
    |> maybe_broadcast_project_record(event)
  end

  defp update_node_typed(node, attrs, event, opts) do
    attrs = normalize_product_record_attrs(attrs)

    incoming_attributes =
      case attrs["node_type"] do
        nil -> attrs["metadata"] || %{}
        nt -> Map.put(attrs["metadata"] || %{}, "node_type", nt)
      end

    merged_attributes = Map.merge(node.attributes || %{}, incoming_attributes)

    result =
      GraphNodes.update_node(node, %{
        title: attrs["title"] || node.title,
        body: attrs["body"] || node.body,
        status: attrs["status"] || node.status,
        attributes: merged_attributes
      })
      |> maybe_broadcast_project_record(event)

    case Keyword.get(opts, :propagate) do
      nil -> result
      type -> maybe_notify_propagation(result, type, :updated)
    end
  end

  defp delete_node_typed(node, event, opts) do
    result = node |> Repo.delete() |> maybe_broadcast_project_record(event)

    case Keyword.get(opts, :propagate) do
      nil -> result
      type -> maybe_notify_propagation(result, type, :deleted)
    end
  end

  defp maybe_filter_node_type_attribute(query, nil), do: query
  defp maybe_filter_node_type_attribute(query, ""), do: query

  defp maybe_filter_node_type_attribute(query, node_type) do
    where(query, [n], fragment("?->>'node_type' = ?", n.attributes, ^to_string(node_type)))
  end

  # -------------------------------------------------------------------
  # Tasks
  # -------------------------------------------------------------------

  def list_tasks(project_or_id, opts \\ []) do
    project_id = project_id(project_or_id)
    status = Keyword.get(opts, :status)
    priority = Keyword.get(opts, :priority)
    search = Keyword.get(opts, :search)

    from(n in GraphNode,
      where: n.project_id == ^project_id and n.type_key == "task" and is_nil(n.archived_at)
    )
    |> maybe_filter_product_record_status(status)
    |> maybe_filter_task_priority(priority)
    |> maybe_filter_title_body_search(search)
    |> order_by([t], desc: t.updated_at)
    |> Repo.all()
  end

  def get_task!(id) do
    Repo.one!(from n in GraphNode, where: n.id == ^id and n.type_key == "task")
  end

  def get_project_task!(project_or_id, id) do
    project_id = project_id(project_or_id)

    Repo.one!(
      from n in GraphNode,
        where: n.project_id == ^project_id and n.id == ^parse_integer(id) and n.type_key == "task"
    )
  end

  def create_task(project_or_id, attrs) when is_map(attrs) do
    project_id = project_id(project_or_id)
    attrs = normalize_product_record_attrs(attrs)

    task_attributes =
      (attrs["metadata"] || %{})
      |> Map.merge(%{
        "assignee" => attrs["assignee"],
        "effort_estimate" => attrs["effort_estimate"],
        "priority" => attrs["priority"] || "medium"
      })
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    node_attrs = %{
      type_key: "task",
      title: attrs["title"],
      body: attrs["body"],
      status: attrs["status"] || "backlog",
      attributes: task_attributes
    }

    GraphNodes.create_node(project_id, node_attrs)
    |> maybe_broadcast_project_record("task.created")
  end

  def update_task(%GraphNode{type_key: "task"} = task, attrs) when is_map(attrs) do
    attrs = normalize_product_record_attrs(attrs)

    incoming_attrs =
      %{
        "assignee" => attrs["assignee"],
        "effort_estimate" => attrs["effort_estimate"],
        "priority" => attrs["priority"]
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    merged_attributes =
      (task.attributes || %{})
      |> Map.merge(attrs["metadata"] || %{})
      |> Map.merge(incoming_attrs)

    GraphNodes.update_node(task, %{
      title: attrs["title"] || task.title,
      body: attrs["body"] || task.body,
      status: attrs["status"] || task.status,
      attributes: merged_attributes
    })
    |> maybe_broadcast_project_record("task.updated")
    |> maybe_notify_propagation("task", :updated)
  end

  def delete_task(%GraphNode{type_key: "task"} = task) do
    task
    |> Repo.delete()
    |> maybe_broadcast_project_record("task.deleted")
    |> maybe_notify_propagation("task", :deleted)
  end

  defp maybe_filter_task_priority(query, nil), do: query
  defp maybe_filter_task_priority(query, ""), do: query

  defp maybe_filter_task_priority(query, priority) do
    where(query, [t], fragment("?->>'priority' = ?", t.attributes, ^to_string(priority)))
  end

  # -------------------------------------------------------------------
  # Learnings
  # -------------------------------------------------------------------

  def list_learnings(project_or_id, opts \\ []) do
    project_id = project_id(project_or_id)
    status = Keyword.get(opts, :status)
    learning_type = Keyword.get(opts, :learning_type)
    search = Keyword.get(opts, :search)

    from(n in GraphNode,
      where: n.project_id == ^project_id and n.type_key == "learning" and is_nil(n.archived_at)
    )
    |> maybe_filter_product_record_status(status)
    |> maybe_filter_learning_type(learning_type)
    |> maybe_filter_title_body_search(search)
    |> order_by([l], desc: l.updated_at)
    |> Repo.all()
  end

  def get_learning!(id) do
    Repo.one!(from n in GraphNode, where: n.id == ^id and n.type_key == "learning")
  end

  def get_project_learning!(project_or_id, id) do
    project_id = project_id(project_or_id)

    Repo.one!(
      from n in GraphNode,
        where:
          n.project_id == ^project_id and n.id == ^parse_integer(id) and
            n.type_key == "learning"
    )
  end

  def create_learning(project_or_id, attrs) when is_map(attrs) do
    project_id = project_id(project_or_id)
    attrs = normalize_product_record_attrs(attrs)

    learning_attributes =
      (attrs["metadata"] || %{})
      |> Map.merge(%{"learning_type" => attrs["learning_type"]})
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    node_attrs = %{
      type_key: "learning",
      title: attrs["title"],
      body: attrs["body"],
      status: attrs["status"] || "active",
      attributes: learning_attributes
    }

    GraphNodes.create_node(project_id, node_attrs)
    |> maybe_broadcast_project_record("learning.created")
  end

  def update_learning(%GraphNode{type_key: "learning"} = learning, attrs) when is_map(attrs) do
    attrs = normalize_product_record_attrs(attrs)

    incoming_attrs =
      if attrs["learning_type"],
        do: %{"learning_type" => attrs["learning_type"]},
        else: %{}

    merged_attributes =
      (learning.attributes || %{})
      |> Map.merge(attrs["metadata"] || %{})
      |> Map.merge(incoming_attrs)

    GraphNodes.update_node(learning, %{
      title: attrs["title"] || learning.title,
      body: attrs["body"] || learning.body,
      status: attrs["status"] || learning.status,
      attributes: merged_attributes
    })
    |> maybe_broadcast_project_record("learning.updated")
    |> maybe_notify_propagation("learning", :updated)
  end

  def delete_learning(%GraphNode{type_key: "learning"} = learning) do
    learning
    |> Repo.delete()
    |> maybe_broadcast_project_record("learning.deleted")
    |> maybe_notify_propagation("learning", :deleted)
  end

  # -------------------------------------------------------------------
  # Graph Edges
  # -------------------------------------------------------------------

  def list_graph_edges(project_or_id, opts \\ []) do
    project_id = project_id(project_or_id)
    kind = Keyword.get(opts, :kind)
    node_type = Keyword.get(opts, :node_type)

    HydraX.Graph.NodeRelationship
    |> where([e], e.project_id == ^project_id)
    |> maybe_filter_edge_kind(kind)
    |> maybe_filter_edge_node_type(node_type)
    |> order_by([e], desc: e.inserted_at)
    |> Repo.all()
  end

  def get_graph_edge!(id), do: Repo.get!(HydraX.Graph.NodeRelationship, id)

  def create_graph_edge(attrs) when is_map(attrs) do
    attrs = HydraX.Runtime.Helpers.normalize_string_keys(attrs)

    # Translate legacy {kind, metadata} shape to substrate {type_key,
    # attributes} expected by NodeRelationship.
    attrs =
      attrs
      |> Map.put_new("type_key", attrs["kind"])
      |> Map.put_new("attributes", attrs["metadata"] || %{})

    %HydraX.Graph.NodeRelationship{}
    |> HydraX.Graph.NodeRelationship.changeset(attrs)
    |> Repo.insert()
  end

  def delete_graph_edge(%HydraX.Graph.NodeRelationship{} = edge) do
    Repo.delete(edge)
  end

  @doc """
  Return all graph nodes and edges for a project as a map suitable for the Graph LiveView.
  """
  def graph_data(project_or_id) do
    project_id = project_id(project_or_id)

    nodes =
      Enum.flat_map(HydraX.Product.Graph.node_types(), fn type ->
        case HydraX.Product.Graph.base_query_for(type) do
          nil ->
            []

          query ->
            try do
              base =
                query
                |> where([r], r.project_id == ^project_id)

              # Source-as-Data: hide non-promoted sources from the default
              # graph (spec §3). They remain queryable via the Library API.
              # `promoted_to_graph` now lives in attributes for substrate
              # source nodes; `archived_at` is still a top-level column.
              base =
                if type in ["source", "signal"] do
                  base
                  |> where(
                    [r],
                    fragment("(?->>'promoted_to_graph')::boolean = true", r.attributes)
                  )
                  |> where([r], is_nil(r.archived_at))
                else
                  base
                end

              base
              |> Repo.all()
              |> Enum.map(fn record ->
                %{
                  id: record.id,
                  type: type,
                  title: Map.get(record, :title, ""),
                  body: Map.get(record, :body, ""),
                  status: Map.get(record, :status, "") || "active",
                  metadata: Map.get(record, :attributes, %{}) || %{},
                  inserted_at: Map.get(record, :inserted_at),
                  updated_at: Map.get(record, :updated_at)
                }
              end)
            rescue
              _ -> []
            end
        end
      end)

    edges =
      list_graph_edges(project_id)
      |> Enum.map(fn e ->
        %{
          id: e.id,
          from_type: e.from_node_type,
          from_id: e.from_node_id,
          to_type: e.to_node_type,
          to_id: e.to_node_id,
          kind: e.type_key,
          weight: e.weight
        }
      end)

    %{nodes: nodes, edges: edges}
  end

  # -------------------------------------------------------------------
  # Graph Flags
  # -------------------------------------------------------------------

  def list_graph_flags(project_or_id, opts \\ []) do
    project_id = project_id(project_or_id)
    status = Keyword.get(opts, :status)
    flag_type = Keyword.get(opts, :flag_type)
    node_type = Keyword.get(opts, :node_type)

    GraphFlag
    |> where([f], f.project_id == ^project_id)
    |> maybe_filter_flag_status(status)
    |> maybe_filter_flag_type(flag_type)
    |> maybe_filter_flag_node_type(node_type)
    |> order_by([f], desc: f.inserted_at)
    |> Repo.all()
  end

  def get_graph_flag!(id), do: Repo.get!(GraphFlag, id)

  def create_graph_flag(attrs) when is_map(attrs) do
    attrs = HydraX.Runtime.Helpers.normalize_string_keys(attrs)

    %GraphFlag{}
    |> GraphFlag.changeset(attrs)
    |> Repo.insert()
  end

  def resolve_graph_flag(%GraphFlag{status: "open"} = flag, resolved_by) do
    flag
    |> GraphFlag.changeset(%{
      "status" => "resolved",
      "resolved_by" => resolved_by,
      "resolved_at" => DateTime.utc_now()
    })
    |> Repo.update()
  end

  def resolve_graph_flag(%GraphFlag{}, _resolved_by), do: {:error, :already_resolved}

  # -------------------------------------------------------------------
  # Constraints
  # -------------------------------------------------------------------

  def list_constraints(project_or_id, opts \\ []) do
    project_id = project_id(project_or_id)
    status = Keyword.get(opts, :status)

    from(n in GraphNode,
      where: n.project_id == ^project_id and n.type_key == "constraint" and is_nil(n.archived_at)
    )
    |> maybe_filter_product_record_status(status)
    |> order_by([c], desc: c.updated_at)
    |> Repo.all()
  end

  def get_constraint!(id) do
    Repo.one!(from n in GraphNode, where: n.id == ^id and n.type_key == "constraint")
  end

  def get_project_constraint!(project_or_id, id) do
    project_id = project_id(project_or_id)

    Repo.one!(
      from n in GraphNode,
        where:
          n.project_id == ^project_id and n.id == ^parse_integer(id) and
            n.type_key == "constraint"
    )
  end

  def create_constraint(project_or_id, attrs) when is_map(attrs) do
    project_id = project_id(project_or_id)
    attrs = normalize_product_record_attrs(attrs)

    node_attrs = %{
      type_key: "constraint",
      title: attrs["title"],
      body: attrs["body"],
      status: attrs["status"] || "active",
      attributes: constraint_attributes(attrs)
    }

    GraphNodes.create_node(project_id, node_attrs)
    |> maybe_broadcast_project_record("constraint.created")
  end

  def update_constraint(%GraphNode{type_key: "constraint"} = constraint, attrs)
      when is_map(attrs) do
    attrs = normalize_product_record_attrs(attrs)

    merged_attributes =
      (constraint.attributes || %{})
      |> Map.merge(attrs["metadata"] || %{})
      |> Map.merge(constraint_attributes(attrs))

    GraphNodes.update_node(constraint, %{
      title: attrs["title"] || constraint.title,
      body: attrs["body"] || constraint.body,
      status: attrs["status"] || constraint.status,
      attributes: merged_attributes
    })
    |> maybe_broadcast_project_record("constraint.updated")
  end

  def delete_constraint(%GraphNode{type_key: "constraint"} = constraint) do
    constraint |> Repo.delete() |> maybe_broadcast_project_record("constraint.deleted")
  end

  defp constraint_attributes(attrs) do
    base = attrs["metadata"] || %{}

    # The legacy `scope` and `enforcement` fields live in attributes now —
    # the substrate's `scope` is memory scope (project/shared) not reach.
    Enum.reduce(
      [
        {"reach_scope", attrs["scope"]},
        {"enforcement", attrs["enforcement"]}
      ],
      base,
      fn {k, v}, acc -> if is_nil(v), do: acc, else: Map.put(acc, k, v) end
    )
  end

  # -------------------------------------------------------------------
  # Routines
  # -------------------------------------------------------------------

  def list_routines(project_or_id, opts \\ []) do
    project_id = project_id(project_or_id)
    status = Keyword.get(opts, :status)

    from(n in GraphNode,
      where: n.project_id == ^project_id and n.type_key == "routine" and is_nil(n.archived_at)
    )
    |> maybe_filter_product_record_status(status)
    |> order_by([r], desc: r.updated_at)
    |> Repo.all()
  end

  def get_routine!(id) do
    Repo.one!(from n in GraphNode, where: n.id == ^id and n.type_key == "routine")
  end

  def get_project_routine!(project_or_id, id) do
    project_id = project_id(project_or_id)

    Repo.one!(
      from n in GraphNode,
        where:
          n.project_id == ^project_id and n.id == ^parse_integer(id) and
            n.type_key == "routine"
    )
  end

  def create_routine(project_or_id, attrs) when is_map(attrs) do
    project_id = project_id(project_or_id)
    attrs = normalize_product_record_attrs(attrs)

    GraphNodes.create_node(project_id, %{
      type_key: "routine",
      title: attrs["title"],
      body: attrs["description"],
      status: attrs["status"] || "active",
      attributes: routine_attributes(attrs)
    })
  end

  def update_routine(%GraphNode{type_key: "routine"} = routine, attrs) when is_map(attrs) do
    attrs = normalize_product_record_attrs(attrs)

    merged_attributes =
      (routine.attributes || %{})
      |> Map.merge(attrs["metadata"] || %{})
      |> Map.merge(routine_attributes(attrs))

    GraphNodes.update_node(routine, %{
      title: attrs["title"] || routine.title,
      body: attrs["description"] || routine.body,
      status: attrs["status"] || routine.status,
      attributes: merged_attributes
    })
  end

  def delete_routine(%GraphNode{type_key: "routine"} = routine), do: Repo.delete(routine)

  def list_routine_runs(routine_or_id, opts \\ []) do
    routine_id =
      case routine_or_id do
        %GraphNode{id: id} -> id
        id -> parse_integer(id)
      end

    limit = Keyword.get(opts, :limit, 20)

    RoutineRun
    |> where([r], r.routine_id == ^routine_id)
    |> order_by([r], desc: r.started_at)
    |> limit(^limit)
    |> Repo.all()
  end

  defp routine_attributes(attrs) do
    [
      {"prompt_template", attrs["prompt_template"]},
      {"assigned_persona", attrs["assigned_persona"]},
      {"schedule_type", attrs["schedule_type"]},
      {"cron_expression", attrs["cron_expression"]},
      {"event_trigger", attrs["event_trigger"]},
      {"timezone", attrs["timezone"]},
      {"output_target", attrs["output_target"]},
      {"last_run_at", attrs["last_run_at"]},
      {"last_run_status", attrs["last_run_status"]},
      {"last_run_tokens", attrs["last_run_tokens"]}
    ]
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  def create_routine_run(attrs) when is_map(attrs) do
    attrs = HydraX.Runtime.Helpers.normalize_string_keys(attrs)
    %RoutineRun{} |> RoutineRun.changeset(attrs) |> Repo.insert()
  end

  # -------------------------------------------------------------------
  # Knowledge Entries
  # -------------------------------------------------------------------

  def list_knowledge_entries(project_or_id, opts \\ []) do
    project_id = project_id(project_or_id)
    status = Keyword.get(opts, :status)
    persona = Keyword.get(opts, :persona)

    query =
      from(n in GraphNode,
        where:
          n.project_id == ^project_id and n.type_key == "knowledge_entry" and
            is_nil(n.archived_at)
      )
      |> maybe_filter_product_record_status(status)

    query =
      if persona do
        p = to_string(persona)

        where(
          query,
          [k],
          fragment("?->'assigned_personas' @> ?", k.attributes, ^[p]) or
            fragment("?->'assigned_personas' @> ?", k.attributes, ^["all"]) or
            fragment(
              "(?->'assigned_personas' IS NULL OR jsonb_array_length(?->'assigned_personas') = 0)",
              k.attributes,
              k.attributes
            )
        )
      else
        query
      end

    query |> order_by([k], desc: k.updated_at) |> Repo.all()
  end

  def get_knowledge_entry!(id) do
    Repo.one!(from n in GraphNode, where: n.id == ^id and n.type_key == "knowledge_entry")
  end

  def get_project_knowledge_entry!(project_or_id, id) do
    project_id = project_id(project_or_id)

    Repo.one!(
      from n in GraphNode,
        where:
          n.project_id == ^project_id and n.id == ^parse_integer(id) and
            n.type_key == "knowledge_entry"
    )
  end

  def create_knowledge_entry(project_or_id, attrs) when is_map(attrs) do
    project_id = project_id(project_or_id)
    attrs = normalize_product_record_attrs(attrs)

    GraphNodes.create_node(project_id, %{
      type_key: "knowledge_entry",
      title: attrs["title"],
      body: attrs["content"],
      status: attrs["status"] || "active",
      attributes: knowledge_entry_attributes(attrs)
    })
  end

  def update_knowledge_entry(%GraphNode{type_key: "knowledge_entry"} = entry, attrs)
      when is_map(attrs) do
    attrs = normalize_product_record_attrs(attrs)

    merged_attributes =
      (entry.attributes || %{})
      |> Map.merge(attrs["metadata"] || %{})
      |> Map.merge(knowledge_entry_attributes(attrs))

    GraphNodes.update_node(entry, %{
      title: attrs["title"] || entry.title,
      body: attrs["content"] || entry.body,
      status: attrs["status"] || entry.status,
      attributes: merged_attributes
    })
  end

  def delete_knowledge_entry(%GraphNode{type_key: "knowledge_entry"} = entry),
    do: Repo.delete(entry)

  defp knowledge_entry_attributes(attrs) do
    [
      {"entry_type", attrs["entry_type"]},
      {"assigned_personas", attrs["assigned_personas"]},
      {"source_type", attrs["source_type"]},
      {"source_url", attrs["source_url"]}
    ]
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc """
  Agent-initiated knowledge proposal. Creates a pending_review entry with
  source_type "generated". Deduplicates against existing entries with the
  same title and entry_type in the project.
  """
  def propose_knowledge(project_or_id, attrs) when is_map(attrs) do
    project_id = project_id(project_or_id)
    attrs = normalize_product_record_attrs(attrs)
    title = Map.get(attrs, "title", "")
    entry_type = Map.get(attrs, "entry_type", "custom")

    # Dedup check: skip if an active or pending entry with same title + type exists
    existing =
      from(n in GraphNode,
        where:
          n.project_id == ^project_id and n.type_key == "knowledge_entry" and
            n.title == ^title and
            fragment("?->>'entry_type' = ?", n.attributes, ^entry_type) and
            n.status in ["active", "pending_review"]
      )
      |> limit(1)
      |> Repo.one()

    if existing do
      {:ok, existing}
    else
      attrs_with_generated =
        attrs
        |> Map.put("status", "pending_review")
        |> Map.put("source_type", "generated")
        |> Map.put_new("assigned_personas", [])

      case create_knowledge_entry(project_id, attrs_with_generated) do
        {:ok, entry} ->
          ProductPubSub.broadcast_project_event(project_id, "knowledge.proposed", entry)
          {:ok, entry}

        error ->
          error
      end
    end
  end

  @doc """
  Review a pending knowledge entry: accept, reject, or edit-then-accept.
  """
  def review_knowledge(entry_or_id, action, attrs \\ %{})

  def review_knowledge(%GraphNode{type_key: "knowledge_entry"} = entry, :accept, attrs) do
    merged = Map.merge(%{"status" => "active"}, normalize_product_record_attrs(attrs))
    update_knowledge_entry(entry, merged)
  end

  def review_knowledge(%GraphNode{type_key: "knowledge_entry"} = entry, :reject, _attrs) do
    update_knowledge_entry(entry, %{"status" => "archived"})
  end

  def review_knowledge(id, action, attrs) when is_integer(id) do
    review_knowledge(get_knowledge_entry!(id), action, attrs)
  end

  # -------------------------------------------------------------------
  # Task Feedback
  # -------------------------------------------------------------------

  def list_task_feedback(task_or_id) do
    task_id =
      case task_or_id do
        %{id: id} -> id
        id -> parse_integer(id)
      end

    TaskFeedback
    |> where([f], f.task_id == ^task_id)
    |> order_by([f], desc: f.inserted_at)
    |> Repo.all()
  end

  def create_task_feedback(task_or_id, attrs) when is_map(attrs) do
    task_id =
      case task_or_id do
        %{id: id} -> id
        id -> parse_integer(id)
      end

    attrs = HydraX.Runtime.Helpers.normalize_string_keys(attrs)

    %TaskFeedback{}
    |> TaskFeedback.changeset(Map.put(attrs, "task_id", task_id))
    |> Repo.insert()
  end

  # -------------------------------------------------------------------
  # Board Sessions
  # -------------------------------------------------------------------

  def list_board_sessions(project_or_id, opts \\ []) do
    project_id = project_id(project_or_id)
    status = Keyword.get(opts, :status)
    search = Keyword.get(opts, :search)

    BoardSession
    |> where([s], s.project_id == ^project_id)
    |> maybe_filter_product_record_status(status)
    |> maybe_filter_title_body_search(search)
    |> order_by([s], desc: s.updated_at)
    |> preload([:board_nodes])
    |> Repo.all()
  end

  def get_board_session!(id) do
    BoardSession
    |> preload([:board_nodes, :board_edges])
    |> Repo.get!(id)
  end

  def get_project_board_session!(project_or_id, id) do
    project_id = project_id(project_or_id)

    BoardSession
    |> where([s], s.project_id == ^project_id and s.id == ^parse_integer(id))
    |> preload([:board_nodes, :board_edges])
    |> Repo.one!()
  end

  def create_board_session(project_or_id, attrs) when is_map(attrs) do
    project_id = project_id(project_or_id)
    attrs = normalize_product_record_attrs(attrs)

    %BoardSession{}
    |> BoardSession.changeset(Map.put(attrs, "project_id", project_id))
    |> Repo.insert()
    |> maybe_broadcast_project_record("board_session.created")
  end

  def update_board_session(%BoardSession{} = session, attrs) when is_map(attrs) do
    attrs = normalize_product_record_attrs(attrs)

    session
    |> BoardSession.changeset(attrs)
    |> Repo.update()
    |> maybe_broadcast_project_record("board_session.updated")
  end

  def delete_board_session(%BoardSession{} = session) do
    session
    |> Repo.delete()
    |> maybe_broadcast_project_record("board_session.deleted")
  end

  # -------------------------------------------------------------------
  # Board Nodes
  # -------------------------------------------------------------------

  def list_board_nodes(session_id, opts \\ []) do
    status = Keyword.get(opts, :status)
    node_type = Keyword.get(opts, :node_type)

    BoardNode
    |> where([n], n.board_session_id == ^parse_integer(session_id))
    |> maybe_filter_product_record_status(status)
    |> maybe_filter_node_type(node_type)
    |> order_by([n], desc: n.inserted_at)
    |> Repo.all()
  end

  def get_board_node!(id), do: Repo.get!(BoardNode, parse_integer(id))

  def get_session_board_node!(session_id, id) do
    BoardNode
    |> where([n], n.board_session_id == ^parse_integer(session_id) and n.id == ^parse_integer(id))
    |> Repo.one!()
  end

  # -------------------------------------------------------------------
  # Board Session Events
  # -------------------------------------------------------------------

  alias HydraX.Product.BoardSessionEvent

  def create_board_session_event(session_id, attrs) when is_map(attrs) do
    %BoardSessionEvent{}
    |> BoardSessionEvent.changeset(Map.put(attrs, "board_session_id", parse_integer(session_id)))
    |> Repo.insert()
    |> tap(fn
      {:ok, event} ->
        # Find project_id from session for broadcast
        session = get_board_session!(event.board_session_id)

        ProductPubSub.broadcast_project_event(
          session.project_id,
          "board_session_event.created",
          %{event: event, board_session_id: event.board_session_id}
        )

      _ ->
        :ok
    end)
  end

  def list_board_session_events(session_id) do
    BoardSessionEvent
    |> where([e], e.board_session_id == ^parse_integer(session_id))
    |> order_by([e], asc: e.inserted_at)
    |> Repo.all()
  end

  # -------------------------------------------------------------------
  # Board Nodes
  # -------------------------------------------------------------------

  def create_board_node(session_id, attrs) when is_map(attrs) do
    session = get_board_session!(parse_integer(session_id))
    attrs = normalize_product_record_attrs(attrs)

    %BoardNode{}
    |> BoardNode.changeset(
      attrs
      |> Map.put("board_session_id", session.id)
      |> Map.put("project_id", session.project_id)
    )
    |> Repo.insert()
    |> tap(fn
      {:ok, node} ->
        ProductPubSub.broadcast_project_event(
          session.project_id,
          "board_node.created",
          %{board_node: node, board_session_id: session.id}
        )

        # Record session event
        event_type =
          if node.node_type == "source_ref", do: "source_uploaded", else: "node_created"

        create_board_session_event(session.id, %{
          "event_type" => event_type,
          "actor_type" => if(node.created_by == "human", do: "human", else: "agent"),
          "actor_name" => node.created_by || "unknown",
          "target_type" => node.node_type,
          "target_id" => node.id,
          "target_title" => node.title
        })

      _ ->
        :ok
    end)
  end

  def update_board_node(%BoardNode{} = node, attrs) when is_map(attrs) do
    attrs = normalize_product_record_attrs(attrs)
    old_status = node.status

    node
    |> BoardNode.changeset(attrs)
    |> Repo.update()
    |> tap(fn
      {:ok, updated} ->
        new_status = updated.status

        if old_status != new_status do
          event_type =
            case new_status do
              "promoted" -> "node_promoted"
              "discarded" -> "node_discarded"
              _ -> nil
            end

          if event_type do
            create_board_session_event(updated.board_session_id, %{
              "event_type" => event_type,
              "actor_type" => "human",
              "actor_name" => "operator",
              "target_type" => updated.node_type,
              "target_id" => updated.id,
              "target_title" => updated.title
            })
          end
        end

      _ ->
        :ok
    end)
    |> maybe_broadcast_project_record("board_node.updated")
  end

  def delete_board_node(%BoardNode{} = node) do
    # Record event before deletion
    create_board_session_event(node.board_session_id, %{
      "event_type" => "node_removed",
      "actor_type" => "human",
      "actor_name" => "operator",
      "target_type" => node.node_type,
      "target_id" => node.id,
      "target_title" => node.title
    })

    node
    |> Repo.delete()
    |> maybe_broadcast_project_record("board_node.deleted")
  end

  # -------------------------------------------------------------------
  # Board Edges
  # -------------------------------------------------------------------

  def create_board_edge(session_id, attrs) when is_map(attrs) do
    attrs =
      attrs
      |> normalize_product_record_attrs()
      |> Map.put("board_session_id", parse_integer(session_id))

    %BoardEdge{}
    |> BoardEdge.changeset(attrs)
    |> Repo.insert()
  end

  def delete_board_edge(%BoardEdge{} = edge) do
    Repo.delete(edge)
  end

  # -------------------------------------------------------------------
  # Board Node Reactions
  # -------------------------------------------------------------------

  @reaction_types ~w(agree question flag star)

  def toggle_board_node_reaction(node_id, reaction_type, user_id)
      when reaction_type in @reaction_types do
    node = Repo.get!(BoardNode, parse_integer(node_id))
    reactions = get_in(node.metadata || %{}, ["reactions"]) || %{}

    current_users = Map.get(reactions, reaction_type, [])

    updated_users =
      if user_id in current_users do
        List.delete(current_users, user_id)
      else
        [user_id | current_users]
      end

    updated_reactions = Map.put(reactions, reaction_type, updated_users)
    updated_metadata = Map.put(node.metadata || %{}, "reactions", updated_reactions)

    node
    |> BoardNode.changeset(%{metadata: updated_metadata})
    |> Repo.update()
    |> tap(fn
      {:ok, updated} ->
        ProductPubSub.broadcast_project_event(
          updated.project_id,
          "board_node.reaction_toggled",
          %{
            board_node_id: updated.id,
            board_session_id: updated.board_session_id,
            reaction: reaction_type,
            user_id: user_id,
            reactions: updated_reactions
          }
        )

      _ ->
        :ok
    end)
  end

  # -------------------------------------------------------------------
  # Prompt Context
  # -------------------------------------------------------------------

  def prompt_context(conversation_or_metadata) do
    metadata = product_metadata(conversation_or_metadata)
    persona = metadata["product_persona"]

    with project_id when is_integer(project_id) <- parse_integer(metadata["product_project_id"]),
         %Project{} = project <- Repo.get(Project, project_id) do
      base = base_prompt_context(project, persona)
      persona_ctx = persona_prompt_context(project.id, persona)

      (base <> "\n\n" <> persona_ctx) |> String.trim()
    else
      _ -> ""
    end
  end

  defp base_prompt_context(project, persona) do
    source_titles =
      project
      |> list_sources()
      |> Enum.take(5)
      |> Enum.map(&("- " <> &1.title))

    source_summary =
      case source_titles do
        [] -> "- none yet"
        values -> Enum.join(values, "\n")
      end

    constraints = list_constraints(project.id, status: "active")

    constraint_section =
      case constraints do
        [] ->
          ""

        items ->
          lines =
            Enum.map(items, fn c ->
              "- [#{c.enforcement}] #{c.title}"
            end)

          "\n## Project constraints (non-negotiable)\n" <> Enum.join(lines, "\n")
      end

    knowledge = list_knowledge_entries(project.id, persona: persona, status: "active")

    knowledge_section =
      case knowledge do
        [] ->
          ""

        entries ->
          entries
          |> Enum.take(3)
          |> Enum.map(fn k ->
            content_preview = String.slice(k.content || "", 0, 500)
            "\n### #{k.title}\n#{content_preview}"
          end)
          |> Enum.join("\n")
          |> then(&("\n## Knowledge\n" <> &1))
      end

    shared_memory_section = shared_memory_section(project)

    """
    Project: #{project.name}
    Persona: #{persona || "product"}
    Grounding rules:
    - Use `source_search` before making factual claims about product research, users, requirements, or source material.
    - Cite grounded claims inline with `[[cite:chunk_id]]` markers immediately after the supported sentence.
    - If the sources do not support a claim, say that the answer is currently ungrounded.
    Available sources:
    #{source_summary}
    #{constraint_section}
    #{knowledge_section}
    #{shared_memory_section}
    #{hydra_meta_section()}
    """
  end

  # Hydra-meta knowledge — shared across personas so any agent can field
  # "what is Stream?", "what does approving a proposal do?", etc. without
  # a dedicated onboarding agent. Keep this terse; it lives in every
  # prompt and shouldn't bloat token use.
  defp hydra_meta_section do
    """

    ## How Hydra works (orient the user when asked)
    Hydra is a workspace where typed knowledge accumulates into a graph and a team of agents reasons over it. Four main surfaces:
    - **Stream** — the project's activity feed. Agents post here when they propose, complete, or get stuck. The "Needs You" tab is the user's queue.
    - **Board** — a freeform canvas for working out ideas before they become structured. Drag, sketch, connect; promote into the graph when ready.
    - **Graph** — every typed node in the project (insights, decisions, requirements, evidence) and the relationships between them. Click any node to see what supports it and what it leads to.
    - **Library** — the user's sources and reference material. Agents read these to ground reasoning, so anything an agent claims should be traceable back to a Library item.

    Schema-change proposals: when an agent wants to add a new node type, relationship type, or flag type, it issues a `schema_change_proposal`. These appear inline in chat as approve/reject cards. Approving applies immediately to the project's schema; rejecting drops the proposal. Users can also propose schema changes directly.

    Node types, relationships, and flags are project-scoped: each project owns its complete schema. The five base primitives (claim, evidence, artifact, activity, entity, agent_role) are shared, but the concrete types extending them differ per project.

    Agents and tasks: a team of specialised agents (Researcher, Strategist, Architect, Designer, Memory) work on the project. Users can ask an agent to do a specific thing, or let it work autonomously — proposals it generates flow into the user's queue. New agents are added from the Agents view; existing ones can be configured there too.

    Adding materials: drop files or paste links into the Library. Sources are chunked and embedded, then made available to all agents for grounded reasoning.

    When the user asks how something works, give a short concrete answer drawing on the section above; don't hand them documentation links — there isn't one yet.
    """
  end

  # Inject the project owner's cross-project "You" scope — principles,
  # identity, recurring constraints — so agents working on *this* project
  # stay consistent with the user's broader worldview. Silent fallback to
  # "" when the owner hasn't seeded a shared scope yet.
  defp shared_memory_section(%Project{workspace_id: nil}), do: ""

  defp shared_memory_section(%Project{} = project) do
    with %HydraX.Accounts.Workspace{created_by_user_id: user_id} when not is_nil(user_id) <-
           Repo.get(HydraX.Accounts.Workspace, project.workspace_id),
         %HydraX.Accounts.SharedScope{} = scope <-
           Repo.get_by(HydraX.Accounts.SharedScope, owner_user_id: user_id) do
      nodes =
        scope.id
        |> HydraX.SharedMemory.list_nodes()
        |> Enum.take(8)

      case nodes do
        [] ->
          ""

        items ->
          lines =
            Enum.map(items, fn n ->
              body = n.body |> to_string() |> String.slice(0, 240)
              "- [#{n.node_type}] #{n.title}: #{body}"
            end)

          "\n## Your identity & cross-project principles\n" <>
            Enum.join(lines, "\n") <>
            "\nHonor these when proposing work — flag a contradiction instead of silently violating them."
      end
    else
      _ -> ""
    end
  end

  defp persona_prompt_context(project_id, "strategist") do
    """
    Active insights: #{count_insight_nodes(project_id)}
    Active decisions: #{count_type_key_nodes(project_id, "decision")}
    When creating requirements, always link to supporting insights.
    When making decisions, record them with decision_create including alternatives considered.
    """
  end

  defp persona_prompt_context(project_id, "architect") do
    """
    Active requirements: #{count_type_key_nodes(project_id, "requirement")}
    Architecture nodes: #{count_active_nodes(project_id, "architecture_node")}
    Always link architecture decisions to the requirements they serve.
    """
  end

  defp persona_prompt_context(project_id, "designer") do
    """
    Active requirements: #{count_type_key_nodes(project_id, "requirement")}
    Design nodes: #{count_active_nodes(project_id, "design_node")}
    Check pattern_check before creating new interaction patterns.
    """
  end

  defp persona_prompt_context(project_id, "memory_agent") do
    """
    You have read-only access to the product graph. You NEVER create or modify nodes.
    Graph summary:
    - Insights: #{count_insight_nodes(project_id)}
    - Decisions: #{count_type_key_nodes(project_id, "decision")}
    - Strategies: #{count_type_key_nodes(project_id, "strategy")}
    - Requirements: #{count_type_key_nodes(project_id, "requirement")}
    - Architecture nodes: #{count_active_nodes(project_id, "architecture_node")}
    - Design nodes: #{count_active_nodes(project_id, "design_node")}
    Use graph_query and trail_trace to find information. Cite specific nodes in your answers.
    """
  end

  defp persona_prompt_context(_project_id, _persona), do: ""

  defp count_active_nodes(project_id, type_key) when is_binary(type_key) do
    count_type_key_nodes(project_id, type_key)
  end

  defp count_active_nodes(project_id, schema) do
    schema
    |> where([r], r.project_id == ^project_id and r.status in ["active", "accepted", "draft"])
    |> Repo.aggregate(:count, :id)
  end

  def tool_modules(conversation_or_metadata) do
    metadata = product_metadata(conversation_or_metadata)
    persona = metadata["product_persona"]

    if parse_integer(metadata["product_project_id"]) do
      tools_for_persona(persona)
    else
      []
    end
  end

  defp tools_for_persona("researcher") do
    [
      @source_search_tool,
      @library_query_tool,
      @library_gaps_tool,
      @insight_create_tool,
      @insight_update_tool,
      @artifact_create_tool,
      @artifact_update_tool,
      @knowledge_propose_tool,
      @knowledge_update_tool
    ]
  end

  defp tools_for_persona("strategist") do
    [
      @source_search_tool,
      @library_query_tool,
      @insight_create_tool,
      @insight_update_tool,
      @requirement_create_tool,
      @decision_create_tool,
      @strategy_create_tool,
      @artifact_create_tool,
      @artifact_update_tool,
      @simulation_propose_tool,
      @knowledge_propose_tool,
      @knowledge_update_tool,
      @project_context_update_tool
    ]
  end

  defp tools_for_persona("architect") do
    [
      @source_search_tool,
      @library_query_tool,
      @architecture_create_tool,
      @architecture_update_tool,
      @feasibility_assess_tool,
      @requirement_create_tool,
      @artifact_create_tool,
      @artifact_update_tool,
      @simulation_propose_tool,
      @knowledge_propose_tool,
      @knowledge_update_tool
    ]
  end

  defp tools_for_persona("designer") do
    [
      @source_search_tool,
      @library_query_tool,
      @design_create_tool,
      @design_update_tool,
      @pattern_check_tool,
      @insight_create_tool,
      @artifact_create_tool,
      @artifact_update_tool,
      @knowledge_propose_tool,
      @knowledge_update_tool
    ]
  end

  defp tools_for_persona("coder") do
    [
      @code_read_tool,
      @code_write_tool,
      @code_edit_tool,
      @code_list_tool,
      @code_search_tool,
      @code_exec_tool,
      @code_test_tool
    ]
  end

  defp tools_for_persona("memory_agent") do
    [
      @source_search_tool,
      @library_query_tool,
      @graph_query_tool,
      @trail_trace_tool,
      @artifact_create_tool,
      @artifact_update_tool
    ]
  end

  defp tools_for_persona(_), do: []

  def parse_citations(project_or_id, content) when is_binary(content) do
    project_id = project_id(project_or_id)
    Citations.parse(project_id, content)
  end

  def list_product_conversations(project_or_id, opts \\ []) do
    project_id = project_id(project_or_id)
    persona = Keyword.get(opts, :persona)
    status = Keyword.get(opts, :status)
    search = Keyword.get(opts, :search)

    ProductConversation
    |> where([conversation], conversation.project_id == ^project_id)
    |> maybe_filter_product_persona(persona)
    |> maybe_filter_product_status(status)
    |> maybe_filter_product_conversation_search(search)
    |> preload(^product_conversation_preloads())
    |> order_by([conversation], desc: conversation.updated_at)
    |> Repo.all()
  end

  def get_product_conversation!(project_or_id, conversation_id, opts \\ []) do
    project_id = project_id(project_or_id)

    conversation =
      ProductConversation
      |> where(
        [conversation],
        conversation.project_id == ^project_id and
          conversation.id == ^parse_integer(conversation_id)
      )
      |> preload([:project, :hydra_conversation])
      |> Repo.one!()

    limit = Keyword.get(opts, :limit)
    before = Keyword.get(opts, :before)

    if limit do
      messages = list_product_messages(conversation.id, limit: limit, before: before)
      %{conversation | product_messages: messages}
    else
      Repo.preload(conversation,
        product_messages: from(m in ProductMessage, order_by: [asc: m.inserted_at])
      )
    end
  end

  def get_product_conversation!(conversation_id) do
    ProductConversation
    |> where([conversation], conversation.id == ^parse_integer(conversation_id))
    |> preload(^product_conversation_preloads())
    |> Repo.one!()
  end

  def update_product_conversation(%ProductConversation{} = conversation, attrs)
      when is_map(attrs) do
    attrs = HydraX.Runtime.Helpers.normalize_string_keys(attrs)

    conversation
    |> ProductConversation.changeset(%{
      "title" => Map.get(attrs, "title", conversation.title),
      "status" => Map.get(attrs, "status", conversation.status),
      "metadata" =>
        if(Map.has_key?(attrs, "metadata"),
          do: Map.merge(conversation.metadata || %{}, attrs["metadata"] || %{}),
          else: conversation.metadata || %{}
        )
    })
    |> Repo.update()
    |> case do
      {:ok, updated} -> {:ok, Repo.preload(updated, product_conversation_preloads())}
      error -> error
    end
  end

  def export_project_snapshot(project_or_id, output_root \\ default_product_export_root()) do
    project = load_project(project_or_id)
    snapshot = project_export_snapshot(project)
    timestamp = Calendar.strftime(DateTime.utc_now(), "%Y%m%d-%H%M%S")
    base_name = "#{project.slug}-#{timestamp}"
    markdown_path = Path.join(output_root, "#{base_name}.md")
    json_path = Path.join(output_root, "#{base_name}.json")
    bundle_dir = Path.join(output_root, "#{base_name}-bundle")

    File.mkdir_p!(output_root)
    File.write!(markdown_path, render_project_export(snapshot))
    File.write!(json_path, Jason.encode!(snapshot, pretty: true))
    write_project_bundle(bundle_dir, snapshot, markdown_path, json_path)

    %{
      project: project,
      snapshot: snapshot,
      markdown_path: markdown_path,
      json_path: json_path,
      bundle_dir: bundle_dir
    }
  end

  defp provision_agent!(project_attrs, persona) do
    project_slug = project_attrs["slug"]
    project_name = project_attrs["name"]
    agent_slug = "project-#{project_slug}-#{String.replace(persona, "_", "-")}"
    workspace_root = Path.join([Config.workspace_root(), "projects", project_slug, persona])

    WorkspaceScaffold.scaffold!(workspace_root, persona, project_name, project_slug)

    attrs = %{
      "name" => "#{project_name} #{String.capitalize(persona)}",
      "slug" => agent_slug,
      "role" => persona_role(persona),
      "workspace_root" => workspace_root,
      "description" => "#{String.capitalize(persona)} agent for #{project_name}",
      "is_default" => false
    }

    case Runtime.save_agent(attrs) do
      {:ok, %AgentProfile{} = agent} -> agent
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp normalize_project_attrs(attrs) do
    attrs = HydraX.Runtime.Helpers.normalize_string_keys(attrs)

    slug =
      case attrs["slug"] do
        value when is_binary(value) and value != "" ->
          value

        _ ->
          attrs["name"]
          |> to_string()
          |> String.downcase()
          |> String.replace(~r/[^a-z0-9]+/u, "-")
          |> String.trim("-")
      end

    attrs
    |> Map.put("slug", slug)
    |> Map.put_new("status", "active")
    |> Map.put_new("metadata", %{})
  end

  defp normalize_source_attrs(attrs) do
    attrs
    |> HydraX.Runtime.Helpers.normalize_string_keys()
    |> Map.put_new("metadata", %{})
    |> Map.put_new("processing_status", "pending")
    |> Map.update("source_type", "text", fn value ->
      value
      |> to_string()
      |> String.trim()
      |> case do
        "" -> "text"
        normalized -> normalized
      end
    end)
  end

  defp parse_source_payload(%{"upload" => %Plug.Upload{} = upload} = attrs) do
    source_type = infer_source_type(attrs["source_type"], upload.filename)
    parser_path = upload_parser_path(upload.filename, source_type)
    File.cp!(upload.path, parser_path)

    try do
      with {:ok, sections} <- Parser.parse(parser_path),
           {:ok, content} <- join_sections(sections) do
        {:ok,
         %{
           source_type: source_type,
           content: content,
           sections: sections,
           metadata:
             Map.merge(attrs["metadata"] || %{}, %{
               "ingest_mode" => "upload",
               "upload_filename" => upload.filename,
               "parser_source" => "file",
               "content_hash" => Parser.content_hash(content)
             })
         }}
      else
        {:error, reason} -> {:error, reason}
      end
    after
      File.rm(parser_path)
    end
  end

  defp parse_source_payload(attrs) do
    content = String.trim(to_string(attrs["content"] || ""))

    if content == "" do
      {:error, :empty_content}
    else
      source_type = infer_source_type(attrs["source_type"], attrs["title"])
      parser_path = parser_path(attrs["title"], source_type)

      with {:ok, sections} <- Parser.parse_content(source_type, content, parser_path) do
        {:ok,
         %{
           source_type: source_type,
           content: content,
           sections: sections,
           metadata:
             Map.merge(attrs["metadata"] || %{}, %{
               "ingest_mode" => "inline",
               "parser_source" => "content",
               "content_hash" => Parser.content_hash(content)
             })
         }}
      end
    end
  end

  defp join_sections(sections) do
    content =
      sections
      |> Enum.map(&String.trim(&1.content || ""))
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n\n")

    if content == "", do: {:error, :empty_content}, else: {:ok, content}
  end

  defp source_error_changeset(project, attrs, reason) do
    attrs = Map.drop(attrs, ["upload"])

    %GraphNode{}
    |> GraphNode.changeset(%{
      project_id: project.id,
      type_key: "source",
      title: attrs["title"],
      body: attrs["content"],
      status: attrs["processing_status"] || "failed",
      attributes: source_attributes(attrs)
    })
    |> Ecto.Changeset.add_error(:body, source_error_message(reason))
  end

  defp source_attributes(attrs) do
    # Fold non-core source columns into the attributes jsonb. The core
    # Node fields (title, body, status, archived_at) are pulled out at
    # the call site.
    base = attrs["metadata"] || %{}

    [
      # Library-spec fields (canonical):
      {"kind", attrs["kind"]},
      {"mime_type", attrs["mime_type"]},
      {"original_filename", attrs["original_filename"]},
      {"original_url", attrs["original_url"]},
      {"byte_size", attrs["byte_size"]},
      {"ingestion_status", attrs["ingestion_status"]},
      {"ingestion_summary", attrs["ingestion_summary"]},
      {"ingestion_failures", attrs["ingestion_failures"]},
      {"recency", attrs["recency"]},
      {"language", attrs["language"]},
      # Legacy/source-as-data fields:
      {"source_type", attrs["source_type"]},
      {"external_ref", attrs["external_ref"]},
      {"reviewed_at", attrs["reviewed_at"]},
      {"promoted_to_graph", attrs["promoted_to_graph"]},
      {"promoted_at", attrs["promoted_at"]}
    ]
    |> Enum.reduce(base, fn {k, v}, acc ->
      if is_nil(v), do: acc, else: Map.put(acc, k, v)
    end)
  end

  defp source_node_attrs(%GraphNode{} = existing, attrs) do
    merged_attributes =
      (existing.attributes || %{})
      |> Map.merge(source_attributes(attrs))

    %{
      title: attrs["title"] || existing.title,
      body: attrs["content"] || existing.body,
      status: attrs["processing_status"] || existing.status,
      attributes: merged_attributes,
      archived_at: attrs["archived_at"] || existing.archived_at
    }
  end

  defp source_error_message({:unsupported_format, format}),
    do: "unsupported source format #{inspect(format)}"

  defp source_error_message({:pdf_extract_failed, code, _output}),
    do: "pdf extraction failed with exit status #{code}"

  defp source_error_message(:pdf_extractor_unavailable),
    do: "pdf extraction requires pdftotext to be installed"

  defp source_error_message(:empty_content), do: "source content cannot be empty"
  defp source_error_message(reason), do: "source ingestion failed: #{inspect(reason)}"

  defp build_chunk_rows(sections, project_id) do
    sections
    |> Enum.flat_map(fn section ->
      section.content
      |> citation_chunks()
      |> Enum.with_index()
      |> Enum.map(fn {content, segment_index} ->
        %{
          content: content,
          token_count: token_count(content),
          metadata:
            Map.merge(section.metadata || %{}, %{
              "project_id" => project_id,
              "segment_index" => segment_index,
              "content_hash" => Parser.content_hash(content),
              "word_count" => word_count(content)
            })
        }
      end)
    end)
  end

  defp citation_chunks(content) do
    words = String.split(content || "", ~r/\s+/, trim: true)

    cond do
      words == [] ->
        []

      length(words) <= @chunk_size_words ->
        [Enum.join(words, " ")]

      true ->
        chunk_words(words, [])
    end
  end

  defp chunk_words([], acc), do: Enum.reverse(acc)

  defp chunk_words(words, acc) do
    chunk = Enum.take(words, @chunk_size_words)
    step = max(@chunk_size_words - @chunk_overlap_words, 1)
    remaining = Enum.drop(words, step)

    next_acc = [Enum.join(chunk, " ") | acc]

    if length(words) <= @chunk_size_words do
      Enum.reverse(next_acc)
    else
      chunk_words(remaining, next_acc)
    end
  end

  defp embed_chunk!(content) do
    {:ok, embedding} = Embeddings.embed(content, dimensions: 768)
    embedding.vector
  end

  defp source_search_candidates(project_id, query, candidate_limit) do
    lexical =
      try do
        SourceChunk
        |> where([chunk], chunk.project_id == ^project_id)
        |> where(
          [chunk],
          fragment("search_vector @@ websearch_to_tsquery('english', ?)", ^query)
        )
        |> order_by(
          [chunk],
          desc: fragment("ts_rank_cd(search_vector, websearch_to_tsquery('english', ?))", ^query),
          desc: chunk.updated_at
        )
        |> limit(^candidate_limit)
        |> select(
          [chunk],
          {chunk,
           fragment("ts_rank_cd(search_vector, websearch_to_tsquery('english', ?))", ^query)}
        )
        |> Repo.all()
        |> Enum.map(fn {chunk, lexical_score} ->
          %{chunk: chunk, lexical_score: lexical_score}
        end)
      rescue
        _ ->
          SourceChunk
          |> where([chunk], chunk.project_id == ^project_id)
          |> where([chunk], like(chunk.content, ^"%#{query}%"))
          |> order_by([chunk], desc: chunk.updated_at)
          |> limit(^candidate_limit)
          |> Repo.all()
          |> Enum.map(&%{chunk: &1, lexical_score: 0.1})
      end

    recent =
      SourceChunk
      |> where([chunk], chunk.project_id == ^project_id)
      |> order_by([chunk], desc: chunk.updated_at)
      |> limit(^candidate_limit)
      |> Repo.all()
      |> Enum.map(&%{chunk: &1, lexical_score: 0.0})

    (lexical ++ recent)
    |> Enum.reduce(%{}, fn candidate, acc ->
      Map.update(acc, candidate.chunk.id, candidate, fn existing ->
        if candidate.lexical_score > existing.lexical_score, do: candidate, else: existing
      end)
    end)
    |> Map.values()
    |> hydrate_source_candidates()
  end

  defp source_query_context(query) do
    {:ok, embedding} = Embeddings.embed(query, dimensions: 768)

    %{
      embedding: embedding.vector,
      terms:
        query
        |> String.downcase()
        |> String.split(~r/[^a-z0-9]+/u, trim: true)
        |> Enum.reject(&(String.length(&1) < 3))
        |> Enum.uniq()
    }
  end

  defp score_source_chunk(candidate, query_context) do
    chunk = candidate.chunk
    lexical_score = candidate.lexical_score || 0.0
    overlap_score = overlap_score(chunk, query_context.terms)
    vector_score = vector_score(chunk, query_context.embedding)
    recency_score = recency_score(chunk)

    score =
      lexical_score * 0.6 +
        overlap_score * 0.25 +
        vector_score * 0.2 +
        recency_score

    %{
      chunk: chunk,
      score: Float.round(score, 6),
      lexical_score: Float.round(lexical_score, 6),
      overlap_score: Float.round(overlap_score, 6),
      vector_score: Float.round(vector_score, 6),
      reasons: source_search_reasons(lexical_score, overlap_score, vector_score)
    }
  end

  defp overlap_score(_chunk, []), do: 0.0

  defp overlap_score(chunk, terms) do
    haystack =
      chunk.content
      |> String.downcase()
      |> String.split(~r/[^a-z0-9]+/u, trim: true)
      |> MapSet.new()

    overlap =
      terms
      |> MapSet.new()
      |> MapSet.intersection(haystack)
      |> MapSet.size()

    overlap / max(length(terms), 1)
  end

  defp vector_score(_chunk, []), do: 0.0

  defp vector_score(chunk, embedding) do
    chunk
    |> chunk_embedding()
    |> Embeddings.cosine_similarity(embedding)
  end

  defp recency_score(%{updated_at: nil}), do: 0.0

  defp recency_score(chunk) do
    age_days = DateTime.diff(DateTime.utc_now(), chunk.updated_at, :day)

    cond do
      age_days <= 1 -> 0.05
      age_days <= 7 -> 0.03
      true -> 0.0
    end
  end

  defp source_search_reasons(lexical_score, overlap_score, vector_score) do
    []
    |> maybe_add_reason(lexical_score > 0, "lexical match")
    |> maybe_add_reason(overlap_score > 0, "term overlap")
    |> maybe_add_reason(vector_score > 0.2, "embedding similarity")
  end

  defp maybe_add_reason(reasons, true, reason), do: reasons ++ [reason]
  defp maybe_add_reason(reasons, false, _reason), do: reasons

  def list_product_messages(conversation_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 30)
    before = Keyword.get(opts, :before)

    query =
      ProductMessage
      |> where([m], m.product_conversation_id == ^conversation_id)
      |> order_by([m], desc: m.inserted_at)
      |> limit(^limit)

    query =
      if before do
        where(query, [m], m.id < ^parse_integer(before))
      else
        query
      end

    query
    |> Repo.all()
    |> Enum.reverse()
  end

  def count_product_messages(conversation_id) do
    ProductMessage
    |> where([m], m.product_conversation_id == ^conversation_id)
    |> Repo.aggregate(:count)
  end

  defp product_conversation_preloads do
    [
      :project,
      :hydra_conversation,
      product_messages: from(message in ProductMessage, order_by: [asc: message.inserted_at])
    ]
  end

  defp insight_preloads do
    [
      insight_evidence: [source_chunk: [:source]],
      requirement_insights: [:requirement]
    ]
  end

  defp requirement_preloads do
    [
      linked_requirement_insights: [insight: [insight_evidence: [source_chunk: [:source]]]]
    ]
  end

  defp maybe_filter_product_persona(query, nil), do: query
  defp maybe_filter_product_persona(query, ""), do: query

  defp maybe_filter_product_persona(query, persona) do
    where(query, [conversation], conversation.persona == ^to_string(persona))
  end

  defp maybe_filter_source_processing_status(query, nil), do: query
  defp maybe_filter_source_processing_status(query, ""), do: query

  defp maybe_filter_source_processing_status(query, status) do
    # processing_status maps to Node.status now.
    where(query, [source], source.status == ^to_string(status))
  end

  defp maybe_filter_source_type(query, nil), do: query
  defp maybe_filter_source_type(query, ""), do: query

  defp maybe_filter_source_type(query, source_type) do
    where(
      query,
      [source],
      fragment("?->>'source_type' = ?", source.attributes, ^to_string(source_type))
    )
  end

  defp maybe_filter_source_search(query, nil), do: query
  defp maybe_filter_source_search(query, ""), do: query

  defp maybe_filter_source_search(query, search) do
    term = "%#{String.trim(to_string(search))}%"

    where(
      query,
      [source],
      ilike(source.title, ^term) or ilike(source.body, ^term) or
        fragment("?->>'external_ref' ILIKE ?", source.attributes, ^term)
    )
  end

  defp maybe_filter_product_record_status(query, nil), do: query
  defp maybe_filter_product_record_status(query, ""), do: query

  defp maybe_filter_product_record_status(query, status) do
    where(query, [record], field(record, :status) == ^to_string(status))
  end

  defp maybe_filter_insight_search(query, nil), do: query
  defp maybe_filter_insight_search(query, ""), do: query

  defp maybe_filter_insight_search(query, search) do
    term = "%#{String.trim(to_string(search))}%"
    where(query, [insight], ilike(insight.title, ^term) or ilike(insight.body, ^term))
  end

  defp maybe_filter_title_body_search(query, nil), do: query
  defp maybe_filter_title_body_search(query, ""), do: query

  defp maybe_filter_title_body_search(query, search) do
    term = "%#{String.trim(to_string(search))}%"
    where(query, [r], ilike(r.title, ^term) or ilike(r.body, ^term))
  end

  defp maybe_filter_node_type(query, nil), do: query
  defp maybe_filter_node_type(query, ""), do: query

  defp maybe_filter_node_type(query, node_type) do
    where(query, [r], r.node_type == ^to_string(node_type))
  end

  defp maybe_filter_learning_type(query, nil), do: query
  defp maybe_filter_learning_type(query, ""), do: query

  defp maybe_filter_learning_type(query, learning_type) do
    where(
      query,
      [r],
      fragment("?->>'learning_type' = ?", r.attributes, ^to_string(learning_type))
    )
  end

  defp maybe_filter_edge_kind(query, nil), do: query
  defp maybe_filter_edge_kind(query, ""), do: query

  defp maybe_filter_edge_kind(query, kind) do
    where(query, [e], e.type_key == ^to_string(kind))
  end

  defp maybe_filter_edge_node_type(query, nil), do: query
  defp maybe_filter_edge_node_type(query, ""), do: query

  defp maybe_filter_edge_node_type(query, node_type) do
    type = to_string(node_type)
    where(query, [e], e.from_node_type == ^type or e.to_node_type == ^type)
  end

  defp maybe_filter_flag_status(query, nil), do: query
  defp maybe_filter_flag_status(query, ""), do: query

  defp maybe_filter_flag_status(query, status) do
    where(query, [f], f.status == ^to_string(status))
  end

  defp maybe_filter_flag_type(query, nil), do: query
  defp maybe_filter_flag_type(query, ""), do: query

  defp maybe_filter_flag_type(query, flag_type) do
    where(query, [f], f.flag_type == ^to_string(flag_type))
  end

  defp maybe_filter_flag_node_type(query, nil), do: query
  defp maybe_filter_flag_node_type(query, ""), do: query

  defp maybe_filter_flag_node_type(query, node_type) do
    where(query, [f], f.node_type == ^to_string(node_type))
  end

  defp maybe_filter_requirement_grounded(query, nil), do: query
  defp maybe_filter_requirement_grounded(query, ""), do: query

  defp maybe_filter_requirement_grounded(query, grounded) do
    case normalize_boolean_filter(grounded) do
      nil ->
        query

      value ->
        where(
          query,
          [r],
          fragment("(?->>'grounded')::boolean = ?", r.attributes, ^value)
        )
    end
  end

  defp maybe_filter_requirement_search(query, nil), do: query
  defp maybe_filter_requirement_search(query, ""), do: query

  defp maybe_filter_requirement_search(query, search) do
    term = "%#{String.trim(to_string(search))}%"
    where(query, [requirement], ilike(requirement.title, ^term) or ilike(requirement.body, ^term))
  end

  defp maybe_filter_project_status(query, nil), do: query
  defp maybe_filter_project_status(query, ""), do: query

  defp maybe_filter_project_status(query, status) do
    where(query, [project], project.status == ^to_string(status))
  end

  defp maybe_filter_project_search(query, nil), do: query
  defp maybe_filter_project_search(query, ""), do: query

  defp maybe_filter_project_search(query, search) do
    term = "%#{String.trim(to_string(search))}%"

    where(
      query,
      [project],
      ilike(project.name, ^term) or ilike(project.slug, ^term) or
        ilike(project.description, ^term)
    )
  end

  defp maybe_filter_product_status(query, nil), do: query
  defp maybe_filter_product_status(query, ""), do: query

  defp maybe_filter_product_status(query, status) do
    where(query, [conversation], conversation.status == ^to_string(status))
  end

  defp maybe_filter_product_conversation_search(query, nil), do: query
  defp maybe_filter_product_conversation_search(query, ""), do: query

  defp maybe_filter_product_conversation_search(query, search) do
    term = "%#{String.trim(to_string(search))}%"
    where(query, [conversation], ilike(conversation.title, ^term))
  end

  defp normalize_boolean_filter(value) when value in [true, "true", 1, "1"], do: true
  defp normalize_boolean_filter(value) when value in [false, "false", 0, "0"], do: false
  defp normalize_boolean_filter(_value), do: nil

  defp load_project_chunks(project_id, chunk_ids) do
    chunks =
      SourceChunk
      |> where([chunk], chunk.project_id == ^project_id and chunk.id in ^chunk_ids)
      |> preload(:source)
      |> Repo.all()

    if length(chunks) == length(Enum.uniq(chunk_ids)) do
      {:ok, sort_by_ids(chunks, chunk_ids)}
    else
      {:error, "must reference source chunks from the same project"}
    end
  end

  defp load_project_insights(_project_id, []), do: {:ok, []}

  defp load_project_insights(project_id, insight_ids) do
    insights =
      from(n in GraphNode,
        where:
          n.project_id == ^project_id and n.id in ^insight_ids and
            n.type_key == "insight"
      )
      |> preload(^insight_preloads())
      |> Repo.all()

    if length(insights) == length(Enum.uniq(insight_ids)) do
      {:ok, sort_by_ids(insights, insight_ids)}
    else
      {:error, "must reference insights from the same project"}
    end
  end

  defp persist_insight_evidence!(insight, chunks, evidence_quotes) do
    Enum.each(chunks, fn chunk ->
      quote =
        Map.get(evidence_quotes, to_string(chunk.id)) || Map.get(evidence_quotes, chunk.id) ||
          chunk.content

      %InsightEvidence{}
      |> InsightEvidence.changeset(%{
        "insight_id" => insight.id,
        "source_chunk_id" => chunk.id,
        "quote" => quote,
        "metadata" => %{"source_id" => chunk.source_id}
      })
      |> Repo.insert()
      |> case do
        {:ok, _evidence} -> :ok
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)

    # Source-as-Data (spec §5): auto-populate source_references when an
    # Insight is extracted from a source. One reference per unique source,
    # `relationship: extracted_from`.
    #
    # Best-effort — a reference failure must not roll back the insight +
    # evidence insert. Evidence already links back to the source via the
    # chunk; the reference is a convenience for Node Detail.
    chunks
    |> Enum.map(& &1.source_id)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.each(fn source_id ->
      excerpt =
        chunks
        |> Enum.find(&(&1.source_id == source_id))
        |> case do
          %{content: c} when is_binary(c) -> String.slice(c, 0, 280)
          _ -> nil
        end

      try do
        HydraX.Product.Library.reference(insight.project_id, source_id, "insight", insight.id, %{
          "relationship" => "extracted_from",
          "excerpt" => excerpt,
          "created_by" => "agent"
        })
      rescue
        _ -> :ok
      catch
        _, _ -> :ok
      end
    end)
  end

  defp persist_requirement_insights!(requirement, insights) do
    Enum.each(insights, fn insight ->
      %RequirementInsight{}
      |> RequirementInsight.changeset(%{
        "requirement_id" => requirement.id,
        "insight_id" => insight.id,
        "metadata" => %{"insight_status" => insight.status}
      })
      |> Repo.insert()
      |> case do
        {:ok, _link} -> :ok
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp delete_insight_evidence!(insight_id) do
    InsightEvidence
    |> where([evidence], evidence.insight_id == ^insight_id)
    |> Repo.delete_all()
  end

  defp delete_requirement_insights!(requirement_id) do
    RequirementInsight
    |> where([link], link.requirement_id == ^requirement_id)
    |> Repo.delete_all()
  end

  defp grounded_requirement?(insights) do
    insights != [] and Enum.all?(insights, &grounded_insight?/1)
  end

  defp grounded_insight?(insight) do
    associated_list(insight.insight_evidence) != []
  end

  defp sort_by_ids(records, ids) do
    index = Map.new(ids |> Enum.with_index(), fn {id, idx} -> {id, idx} end)
    Enum.sort_by(records, &Map.get(index, &1.id, 0))
  end

  defp normalize_product_record_attrs(attrs) do
    attrs
    |> HydraX.Runtime.Helpers.normalize_string_keys()
    |> Map.put_new("metadata", %{})
  end

  defp normalize_integer_list(nil), do: []

  defp normalize_integer_list(values) when is_list(values) do
    values
    |> Enum.map(&parse_integer/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp normalize_integer_list(_values), do: []

  defp insight_error_changeset(project_id, attrs, field, message) do
    %GraphNode{}
    |> GraphNode.changeset(%{
      project_id: project_id,
      type_key: "insight",
      title: attrs["title"],
      body: attrs["body"],
      status: attrs["status"] || "draft",
      attributes: attrs["metadata"] || %{}
    })
    |> Ecto.Changeset.add_error(product_error_field(field), message)
  end

  defp requirement_error_changeset(project_id, attrs, field, message) do
    %GraphNode{}
    |> GraphNode.changeset(%{
      project_id: project_id,
      type_key: "requirement",
      title: attrs["title"],
      body: attrs["body"],
      status: attrs["status"] || "draft",
      attributes: Map.put(attrs["metadata"] || %{}, "grounded", false)
    })
    |> Ecto.Changeset.add_error(product_error_field(field), message)
  end

  defp persist_source_chunks(source, parsed, project_id) do
    Repo.transaction(fn ->
      chunks =
        parsed.sections
        |> build_chunk_rows(project_id)
        |> Enum.with_index()
        |> Enum.map(fn {chunk, ordinal} ->
          embedding = embed_chunk!(chunk.content)

          %SourceChunk{}
          |> SourceChunk.changeset(%{
            "project_id" => project_id,
            "source_id" => source.id,
            "ordinal" => ordinal,
            "content" => chunk.content,
            "token_count" => chunk.token_count,
            "metadata" => chunk.metadata,
            "embedding" => embedding
          })
          |> Repo.insert()
          |> case do
            {:ok, chunk} -> chunk
            {:error, changeset} -> Repo.rollback(changeset)
          end
        end)

      merged_attributes =
        (source.attributes || %{})
        |> Map.merge(parsed.metadata || %{})
        |> Map.merge(%{
          "chunk_count" => length(chunks),
          "word_count" => word_count(parsed.content)
        })

      source
      |> GraphNode.changeset(%{
        status: "completed",
        attributes: merged_attributes
      })
      |> Repo.update()
      |> case do
        {:ok, source} -> Repo.preload(source, :source_chunks, force: true)
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
    |> unwrap_transaction()
  end

  defp maybe_mirror_source_memories(source, project, attrs) do
    if mirror_to_memory?(attrs) do
      case mirror_source_memories(source, project) do
        {:ok, mirrored_source} ->
          ProductPubSub.broadcast_project_event(project.id, "source.updated", mirrored_source)
          mirrored_source

        {:error, reason} ->
          failed_source = mark_source_memory_mirror_failed(source, reason)
          ProductPubSub.broadcast_project_event(project.id, "source.updated", failed_source)
          failed_source
      end
    else
      source
    end
  end

  defp mirror_source_memories(source, project) do
    agents = mirror_agents(project)

    try do
      mirrored_memory_ids =
        for agent <- agents,
            chunk <- Enum.sort_by(source.source_chunks || [], & &1.ordinal) do
          {:ok, memory} =
            Memory.create_memory(%{
              agent_id: agent.id,
              type: "Observation",
              status: "active",
              importance: 0.58,
              content: chunk.content,
              metadata: source_memory_metadata(project, source, chunk, agent)
            })

          memory.id
        end

      Enum.each(agents, &Runtime.refresh_agent_bulletin!(&1.id))

      {:ok,
       update_source_memory_mirror(source, %{
         "enabled" => true,
         "status" => "completed",
         "mirrored_agent_ids" => Enum.map(agents, & &1.id),
         "mirrored_memory_count" => length(mirrored_memory_ids),
         "mirrored_memory_ids" => mirrored_memory_ids,
         "mirrored_at" => DateTime.utc_now()
       })}
    rescue
      error ->
        {:error, Exception.message(error)}
    end
  end

  defp mirror_agents(project) do
    project
    |> load_project()
    |> then(fn loaded ->
      [
        loaded.researcher_agent || Runtime.get_agent!(loaded.researcher_agent_id),
        loaded.strategist_agent || Runtime.get_agent!(loaded.strategist_agent_id)
      ]
    end)
  end

  defp update_source_memory_mirror(source, mirror_state) do
    attrs = Map.put(source.attributes || %{}, "memory_mirror", mirror_state)

    source
    |> GraphNode.changeset(%{attributes: attrs})
    |> Repo.update!()
    |> Repo.preload(:source_chunks, force: true)
  end

  defp mark_source_memory_mirror_failed(source, reason) do
    update_source_memory_mirror(source, %{
      "enabled" => true,
      "status" => "failed",
      "error" => inspect(reason),
      "failed_at" => DateTime.utc_now()
    })
  end

  defp mirror_to_memory?(attrs) do
    direct = Map.get(attrs, "mirror_to_memory")
    metadata = Map.get(attrs, "metadata") || %{}
    truthy?(direct) or truthy?(Map.get(metadata, "mirror_to_memory"))
  end

  defp truthy?(value) when value in [true, "true", 1, "1", "yes", "on"], do: true
  defp truthy?(_value), do: false

  defp source_memory_metadata(project, source, chunk, agent) do
    %{
      "source_file" => source_memory_file(project, source),
      "source_section" =>
        get_in(chunk.metadata || %{}, ["section"]) || "Chunk #{chunk.ordinal + 1}",
      "source_channel" => "product_source",
      "product_project_id" => project.id,
      "product_project_slug" => project.slug,
      "product_source_id" => source.id,
      "product_source_title" => source.title,
      "product_source_chunk_id" => chunk.id,
      "product_source_type" => get_in(source.attributes || %{}, ["source_type"]),
      "product_source_agent_role" => agent.role,
      "source_kind" => "product_source",
      "mirror_reason" => "source_ingestion"
    }
  end

  defp source_memory_file(project, source) do
    safe_title =
      source.title
      |> to_string()
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/u, "-")
      |> String.trim("-")

    "product/#{project.slug}/sources/#{source.id}-#{safe_title}"
  end

  defp mark_source_failed(source) do
    merged_attributes =
      Map.put(source.attributes || %{}, "last_error", "source ingestion failed")

    source
    |> GraphNode.changeset(%{status: "failed", attributes: merged_attributes})
    |> Repo.update!()
    |> Repo.preload(:source_chunks, force: true)
  end

  defp maybe_broadcast_project_record({:ok, %{project_id: project_id} = record}, event) do
    ProductPubSub.broadcast_project_event(project_id, event, record)
    {:ok, record}
  end

  defp maybe_broadcast_project_record(result, _event), do: result

  defp maybe_notify_propagation({:ok, record} = result, node_type, change_type) do
    if Map.has_key?(record, :project_id) do
      HydraX.Product.Propagation.notify_change(
        record.project_id,
        node_type,
        record.id,
        change_type
      )
    end

    result
  end

  defp maybe_notify_propagation(result, _node_type, _change_type), do: result

  @doc false
  def maybe_notify_coherence({:ok, record} = result, node_type, change_type)
      when change_type in [:created, :updated] do
    if Map.has_key?(record, :project_id) do
      HydraX.Coherence.DetectionService.on_project_node_change(
        record.project_id,
        to_string(node_type),
        record.id
      )
    end

    result
  end

  def maybe_notify_coherence(result, _node_type, _change_type), do: result

  defp unwrap_transaction({:ok, value}), do: {:ok, value}
  defp unwrap_transaction({:error, %Ecto.Changeset{} = changeset}), do: {:error, changeset}
  defp unwrap_transaction({:error, reason}), do: {:error, reason}

  defp product_error_field("evidence_chunk_ids"), do: :metadata
  defp product_error_field("insight_ids"), do: :metadata
  defp product_error_field("status"), do: :status
  defp product_error_field(_field), do: :metadata

  defp hydrate_source_candidates(candidates) do
    chunks =
      candidates
      |> Enum.map(& &1.chunk)
      |> Repo.preload(:source)

    lexical_scores =
      candidates
      |> Map.new(fn candidate -> {candidate.chunk.id, candidate.lexical_score} end)

    Enum.map(chunks, fn chunk ->
      chunk =
        if match?(%GraphNode{type_key: "source"}, chunk.source) do
          %{chunk | source: hydrate_source_compat(chunk.source)}
        else
          chunk
        end

      %{chunk: chunk, lexical_score: Map.get(lexical_scores, chunk.id, 0.0)}
    end)
  end

  defp hydrate_source_compat(%GraphNode{type_key: "source"} = source) do
    attrs = source.attributes || %{}

    %{
      source
      | processing_status: source.status,
        source_type: Map.get(attrs, "source_type"),
        content: source.body,
        external_ref: Map.get(attrs, "external_ref"),
        metadata: attrs
    }
  end

  defp hydrate_source_compat(source), do: source

  defp chunk_embedding(chunk) do
    case chunk.embedding do
      %Pgvector{} = vector -> Pgvector.to_list(vector)
      vector when is_list(vector) -> vector
      _ -> []
    end
  end

  defp word_count(content) do
    content
    |> String.split(~r/\s+/, trim: true)
    |> length()
  end

  defp token_count(content), do: word_count(content)

  defp project_export_snapshot(project) do
    conversations = list_product_conversations(project)

    %{
      project: project_export_json(project),
      sources: Enum.map(list_sources(project), &source_export_json/1),
      insights: Enum.map(list_insights(project), &insight_export_json/1),
      requirements: Enum.map(list_requirements(project), &requirement_export_json/1),
      conversations: Enum.map(conversations, &conversation_export_json/1)
    }
  end

  defp project_export_json(project) do
    %{
      id: project.id,
      name: project.name,
      slug: project.slug,
      description: project.description,
      status: project.status,
      metadata: project.metadata || %{},
      researcher_agent_id: project.researcher_agent_id,
      strategist_agent_id: project.strategist_agent_id,
      inserted_at: project.inserted_at,
      updated_at: project.updated_at
    }
  end

  defp source_export_json(source) do
    attrs = source.attributes || %{}

    %{
      id: source.id,
      project_id: source.project_id,
      title: source.title,
      source_type: Map.get(attrs, "source_type"),
      content: source.body,
      external_ref: Map.get(attrs, "external_ref"),
      processing_status: source.status,
      metadata: attrs,
      source_chunks:
        Enum.map(source.source_chunks || [], fn chunk ->
          %{
            id: chunk.id,
            ordinal: chunk.ordinal,
            content: chunk.content,
            token_count: chunk.token_count,
            metadata: chunk.metadata || %{},
            inserted_at: chunk.inserted_at,
            updated_at: chunk.updated_at
          }
        end),
      inserted_at: source.inserted_at,
      updated_at: source.updated_at
    }
  end

  defp insight_export_json(insight) do
    %{
      id: insight.id,
      project_id: insight.project_id,
      title: insight.title,
      body: insight.body,
      status: insight.status,
      metadata: insight.attributes || %{},
      evidence:
        Enum.map(associated_list(insight.insight_evidence), fn evidence ->
          %{
            id: evidence.id,
            source_chunk_id: evidence.source_chunk_id,
            quote: evidence.quote,
            metadata: evidence.metadata || %{},
            source_chunk:
              if(evidence.source_chunk,
                do: %{
                  id: evidence.source_chunk.id,
                  source_id: evidence.source_chunk.source_id,
                  source_title:
                    evidence.source_chunk.source && evidence.source_chunk.source.title,
                  content: evidence.source_chunk.content,
                  ordinal: evidence.source_chunk.ordinal
                }
              )
          }
        end),
      requirement_ids:
        Enum.map(associated_list(insight.requirement_insights), & &1.requirement_id),
      inserted_at: insight.inserted_at,
      updated_at: insight.updated_at
    }
  end

  defp requirement_export_json(requirement) do
    attrs = requirement.attributes || %{}

    %{
      id: requirement.id,
      project_id: requirement.project_id,
      title: requirement.title,
      body: requirement.body,
      status: requirement.status,
      grounded: Map.get(attrs, "grounded", false),
      metadata: attrs,
      insights:
        Enum.map(associated_list(requirement.linked_requirement_insights), fn link ->
          insight = link.insight

          %{
            id: insight.id,
            title: insight.title,
            status: insight.status,
            evidence_chunk_ids:
              Enum.map(associated_list(insight.insight_evidence), & &1.source_chunk_id)
          }
        end),
      inserted_at: requirement.inserted_at,
      updated_at: requirement.updated_at
    }
  end

  defp conversation_export_json(conversation) do
    hydra = conversation.hydra_conversation

    %{
      id: conversation.id,
      project_id: conversation.project_id,
      hydra_conversation_id: conversation.hydra_conversation_id,
      persona: conversation.persona,
      title: conversation.title,
      status: conversation.status,
      metadata: conversation.metadata || %{},
      hydra: %{
        id: hydra && hydra.id,
        channel: hydra && hydra.channel,
        external_ref: hydra && hydra.external_ref,
        status: hydra && hydra.status
      },
      messages:
        Enum.map(conversation.product_messages || [], fn message ->
          %{
            id: message.id,
            hydra_turn_id: message.hydra_turn_id,
            role: message.role,
            content: message.content,
            citations: message.citations || [],
            metadata: message.metadata || %{},
            inserted_at: message.inserted_at,
            updated_at: message.updated_at
          }
        end),
      inserted_at: conversation.inserted_at,
      updated_at: conversation.updated_at
    }
  end

  defp render_project_export(snapshot) do
    project = snapshot.project

    [
      "# #{project.name} Product Export",
      "",
      "- project_id: #{project.id}",
      "- slug: #{project.slug}",
      "- status: #{project.status}",
      "- sources: #{length(snapshot.sources)}",
      "- insights: #{length(snapshot.insights)}",
      "- requirements: #{length(snapshot.requirements)}",
      "- conversations: #{length(snapshot.conversations)}",
      "",
      "## Sources",
      ""
    ]
    |> Kernel.++(render_source_export_lines(snapshot.sources))
    |> Kernel.++(["", "## Insights", ""])
    |> Kernel.++(render_insight_export_lines(snapshot.insights))
    |> Kernel.++(["", "## Requirements", ""])
    |> Kernel.++(render_requirement_export_lines(snapshot.requirements))
    |> Kernel.++(["", "## Conversations", ""])
    |> Kernel.++(render_conversation_export_lines(snapshot.conversations))
    |> Enum.join("\n")
  end

  defp render_source_export_lines([]), do: ["- none"]

  defp render_source_export_lines(sources) do
    Enum.flat_map(sources, fn source ->
      attrs = Map.get(source, :attributes) || Map.get(source, :metadata) || %{}
      source_type = Map.get(source, :source_type) || Map.get(attrs, "source_type")
      chunks = Map.get(source, :source_chunks) || []
      status = Map.get(source, :status) || Map.get(source, :processing_status)

      [
        "- [#{source.id}] #{source.title} (#{source_type}) chunks=#{length(chunks)} status=#{status}"
      ]
    end)
  end

  defp render_insight_export_lines([]), do: ["- none"]

  defp render_insight_export_lines(insights) do
    Enum.flat_map(insights, fn insight ->
      [
        "- [#{insight.id}] #{insight.title} status=#{insight.status} evidence=#{length(insight.evidence)}",
        "  #{insight.body}"
      ]
    end)
  end

  defp render_requirement_export_lines([]), do: ["- none"]

  defp render_requirement_export_lines(requirements) do
    Enum.flat_map(requirements, fn requirement ->
      [
        "- [#{requirement.id}] #{requirement.title} status=#{requirement.status} grounded=#{if(requirement.grounded, do: "yes", else: "no")} insights=#{length(requirement.insights || [])}",
        "  #{requirement.body}"
      ]
    end)
  end

  defp render_conversation_export_lines([]), do: ["- none"]

  defp render_conversation_export_lines(conversations) do
    Enum.flat_map(conversations, fn conversation ->
      [
        "- [#{conversation.id}] #{conversation.title || "Untitled"} persona=#{conversation.persona} messages=#{length(conversation.messages)} hydra=#{conversation.hydra_conversation_id}"
      ]
    end)
  end

  defp write_project_bundle(bundle_dir, snapshot, markdown_path, json_path) do
    File.mkdir_p!(bundle_dir)

    manifest = %{
      exported_at: DateTime.utc_now(),
      project_id: snapshot.project.id,
      project_slug: snapshot.project.slug,
      markdown_path: markdown_path,
      json_path: json_path,
      counts: %{
        sources: length(snapshot.sources),
        insights: length(snapshot.insights),
        requirements: length(snapshot.requirements),
        conversations: length(snapshot.conversations)
      }
    }

    File.write!(Path.join(bundle_dir, "manifest.json"), Jason.encode!(manifest, pretty: true))

    File.write!(
      Path.join(bundle_dir, "project.json"),
      Jason.encode!(snapshot.project, pretty: true)
    )

    File.write!(
      Path.join(bundle_dir, "sources.json"),
      Jason.encode!(snapshot.sources, pretty: true)
    )

    File.write!(
      Path.join(bundle_dir, "insights.json"),
      Jason.encode!(snapshot.insights, pretty: true)
    )

    File.write!(
      Path.join(bundle_dir, "requirements.json"),
      Jason.encode!(snapshot.requirements, pretty: true)
    )

    File.write!(
      Path.join(bundle_dir, "conversations.json"),
      Jason.encode!(snapshot.conversations, pretty: true)
    )

    write_product_transcripts(bundle_dir, snapshot.conversations)
  end

  defp write_product_transcripts(bundle_dir, conversations) do
    transcripts_dir = Path.join(bundle_dir, "transcripts")
    File.mkdir_p!(transcripts_dir)

    Enum.each(conversations, fn conversation ->
      export = Runtime.export_conversation_transcript!(conversation.hydra_conversation_id)
      destination = Path.join(transcripts_dir, Path.basename(export.path))
      File.cp!(export.path, destination)
    end)
  end

  defp default_product_export_root do
    Path.join(Config.install_root(), "product_exports")
  end

  defp infer_source_type(source_type, filename_or_title) do
    candidate =
      source_type
      |> to_string()
      |> String.trim()
      |> String.downcase()

    cond do
      candidate in ["markdown", "md"] -> "markdown"
      candidate in ["json"] -> "json"
      candidate in ["pdf"] -> "pdf"
      candidate in ["text", "txt", ""] -> inferred_source_type_from_name(filename_or_title)
      true -> candidate
    end
  end

  defp inferred_source_type_from_name(name) do
    case Path.extname(to_string(name || "")) |> String.downcase() do
      ".md" -> "markdown"
      ".json" -> "json"
      ".pdf" -> "pdf"
      _ -> "text"
    end
  end

  defp parser_path(title, source_type) do
    base =
      title
      |> to_string()
      |> String.trim()
      |> case do
        "" -> "inline"
        value -> value
      end

    ext =
      case source_type do
        "markdown" -> ".md"
        "json" -> ".json"
        "pdf" -> ".pdf"
        _ -> ".txt"
      end

    if String.ends_with?(base, ext), do: base, else: base <> ext
  end

  defp upload_parser_path(filename, source_type) do
    Path.join(
      System.tmp_dir!(),
      "hydra-product-#{System.unique_integer([:positive])}#{parser_ext(filename, source_type)}"
    )
  end

  defp parser_ext(filename, source_type) do
    ext = Path.extname(to_string(filename || ""))

    case {String.downcase(ext), source_type} do
      {".md", _} -> ".md"
      {".json", _} -> ".json"
      {".pdf", _} -> ".pdf"
      {".txt", _} -> ".txt"
      {_, "markdown"} -> ".md"
      {_, "json"} -> ".json"
      {_, "pdf"} -> ".pdf"
      _ -> ".txt"
    end
  end

  defp persona_role("researcher"), do: "researcher"
  defp persona_role("strategist"), do: "planner"
  defp persona_role("architect"), do: "builder"
  defp persona_role("designer"), do: "designer"
  defp persona_role("memory_agent"), do: "operator"

  defp count_project_records(schema, project_id) do
    schema
    |> where([record], record.project_id == ^project_id)
    |> Repo.aggregate(:count, :id)
  end

  defp associated_list(%Ecto.Association.NotLoaded{}), do: []
  defp associated_list(nil), do: []
  defp associated_list(list) when is_list(list), do: list

  defp count_insight_nodes(project_id) do
    count_type_key_nodes(project_id, "insight")
  end

  defp count_type_key_nodes(project_id, type_key, mode \\ :active)

  defp count_type_key_nodes(project_id, type_key, :active) do
    from(n in GraphNode,
      where:
        n.project_id == ^project_id and n.type_key == ^type_key and
          n.status in ["active", "accepted", "draft"]
    )
    |> Repo.aggregate(:count, :id)
  end

  defp count_type_key_nodes(project_id, type_key, :all) do
    from(n in GraphNode,
      where: n.project_id == ^project_id and n.type_key == ^type_key
    )
    |> Repo.aggregate(:count, :id)
  end

  # -------------------------------------------------------------------
  # Artifacts
  # -------------------------------------------------------------------

  def list_artifacts(project_or_id, opts \\ []) do
    project_id = project_id(project_or_id)
    status = Keyword.get(opts, :status)
    artifact_type = Keyword.get(opts, :artifact_type)
    search = Keyword.get(opts, :search)

    from(n in GraphNode,
      where: n.project_id == ^project_id and n.type_key == "artifact" and is_nil(n.archived_at)
    )
    |> then(fn q ->
      if status, do: where(q, [a], a.status == ^status), else: q
    end)
    |> then(fn q ->
      if artifact_type,
        do:
          where(
            q,
            [a],
            fragment("?->>'artifact_type' = ?", a.attributes, ^to_string(artifact_type))
          ),
        else: q
    end)
    |> then(fn q ->
      if search && search != "" do
        escaped =
          search
          |> String.replace("\\", "\\\\")
          |> String.replace("%", "\\%")
          |> String.replace("_", "\\_")

        where(q, [a], ilike(a.title, ^"%#{escaped}%"))
      else
        q
      end
    end)
    |> order_by([a], desc: a.updated_at)
    |> Repo.all()
  end

  def get_artifact!(project_or_id, artifact_id) do
    project_id = project_id(project_or_id)

    Repo.one!(
      from n in GraphNode,
        where: n.project_id == ^project_id and n.id == ^artifact_id and n.type_key == "artifact"
    )
  end

  def create_artifact(project_or_id, attrs) do
    project_id = project_id(project_or_id)
    attrs = HydraX.Runtime.Helpers.normalize_string_keys(attrs)

    artifact_attributes =
      (attrs["metadata"] || %{})
      |> Map.merge(%{
        "artifact_type" => attrs["artifact_type"],
        "owner_persona" => attrs["owner_persona"],
        "last_updated_by" => attrs["last_updated_by"]
      })
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    node_attrs = %{
      type_key: "artifact",
      title: attrs["title"],
      body: attrs["body"],
      status: attrs["status"] || "active",
      attributes: artifact_attributes
    }

    case GraphNodes.create_node(project_id, node_attrs) do
      {:ok, artifact} ->
        ProductPubSub.broadcast_project_event(project_id, "artifact.created", artifact)
        {:ok, artifact}

      error ->
        error
    end
  end

  @doc """
  Updates an artifact body, creating a version snapshot of the previous content.
  Uses Ecto.Multi for atomicity. The substrate's `lock_version` provides
  optimistic locking and doubles as the current version number.
  """
  def update_artifact(project_or_id, artifact_id, attrs) do
    project_id = project_id(project_or_id)
    artifact = get_artifact!(project_id, artifact_id)

    attrs = HydraX.Runtime.Helpers.normalize_string_keys(attrs)
    updated_by = Map.get(attrs, "last_updated_by", "system")
    change_summary = Map.get(attrs, "change_summary")

    merged_attributes =
      (artifact.attributes || %{})
      |> Map.merge(attrs["metadata"] || %{})
      |> Map.put("last_updated_by", updated_by)
      |> Map.put("last_change_summary", change_summary)

    Ecto.Multi.new()
    |> Ecto.Multi.insert(:version, fn _changes ->
      ArtifactVersion.changeset(%ArtifactVersion{}, %{
        "artifact_id" => artifact.id,
        "version" => artifact.lock_version,
        "body" => artifact.body,
        "change_summary" => change_summary,
        "updated_by" => updated_by,
        "metadata" => %{}
      })
    end)
    |> Ecto.Multi.update(:artifact, fn _changes ->
      GraphNode.transition_changeset(artifact, %{
        title: attrs["title"] || artifact.title,
        body: attrs["body"] || artifact.body,
        status: attrs["status"] || artifact.status,
        attributes: merged_attributes
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{artifact: updated_artifact}} ->
        ProductPubSub.broadcast_project_event(project_id, "artifact.updated", %{
          artifact: updated_artifact,
          change_summary: change_summary,
          updated_by: updated_by
        })

        {:ok, updated_artifact}

      {:error, :artifact, %Ecto.Changeset{} = changeset, _changes} ->
        {:error, changeset}

      {:error, :artifact, %Ecto.StaleEntryError{}, _changes} ->
        {:error, :stale_version}

      {:error, :version, changeset, _changes} ->
        {:error, changeset}
    end
  end

  def list_artifact_versions(project_or_id, artifact_id) do
    project_id = project_id(project_or_id)
    # Verify artifact belongs to project (raises if not found)
    _artifact = get_artifact!(project_id, artifact_id)

    ArtifactVersion
    |> where([v], v.artifact_id == ^artifact_id)
    |> order_by([v], desc: v.version)
    |> Repo.all()
  end

  @doc """
  Start the initiative engine for a project. Safe to call multiple times —
  will no-op if the engine is already running.
  """
  def start_initiative_engine(project_or_id) do
    project_id = project_id(project_or_id)

    case HydraX.Product.Initiative.start_link(project_id) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      error -> error
    end
  end

  defp maybe_start_initiative_engine(%Project{trust_level: "cautious"}), do: :ok

  defp maybe_start_initiative_engine(%Project{id: project_id}) do
    start_initiative_engine(project_id)
  end

  defp provision_default_artifacts!(project) do
    # Per the Part 1 amendment, projects start with no schema. Only
    # provision defaults if the project has the `artifact` type defined
    # (e.g. it had a pretrained project applied).
    case HydraX.Graph.SchemaRegistry.fetch_node_type(project.id, "artifact") do
      :error ->
        :ok

      {:ok, _} ->
        defaults = [
          %{
            "title" => "Project Summary",
            "artifact_type" => "project_summary",
            "body" =>
              "# #{project.name}\n\nProject summary will be maintained as the product graph evolves.",
            "owner_persona" => "memory_agent",
            "last_updated_by" => "system"
          },
          %{
            "title" => "Decision Log",
            "artifact_type" => "decision_log",
            "body" => "# Decision Log\n\nChronological record of all decisions with reasoning.",
            "owner_persona" => "memory_agent",
            "last_updated_by" => "system"
          }
        ]

        Enum.each(defaults, fn attrs ->
          {:ok, _} = create_artifact(project.id, attrs)
        end)
    end
  end

  defp load_project(%Project{} = project),
    do: Repo.preload(project, @agent_preloads)

  defp load_project(id) when is_integer(id), do: get_project!(id)
  defp load_project(id) when is_binary(id), do: id |> String.to_integer() |> get_project!()

  defp project_id(%Project{} = project), do: project.id
  defp project_id(id) when is_integer(id), do: id
  defp project_id(id) when is_binary(id), do: String.to_integer(id)

  defp product_metadata(%Conversation{} = conversation), do: conversation.metadata || %{}
  defp product_metadata(metadata) when is_map(metadata), do: metadata
  defp product_metadata(_value), do: %{}

  defp parse_integer(value) when is_integer(value), do: value

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _ -> nil
    end
  end

  defp parse_integer(_value), do: nil
end
