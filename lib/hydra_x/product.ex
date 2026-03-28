defmodule HydraX.Product do
  @moduledoc """
  Product-domain data and provisioning helpers built inside the Hydra-X repo.
  """

  import Ecto.Query

  alias HydraX.Config
  alias HydraX.Embeddings
  alias HydraX.Ingest.Parser
  alias HydraX.Memory
  alias HydraX.Product.ArchitectureNode
  alias HydraX.Product.Citations
  alias HydraX.Product.Constraint
  alias HydraX.Product.Decision
  alias HydraX.Product.DesignNode
  alias HydraX.Product.GraphEdge
  alias HydraX.Product.GraphFlag
  alias HydraX.Product.Insight
  alias HydraX.Product.InsightEvidence
  alias HydraX.Product.KnowledgeEntry
  alias HydraX.Product.Learning
  alias HydraX.Product.Project
  alias HydraX.Product.ProductConversation
  alias HydraX.Product.ProductMessage
  alias HydraX.Product.PubSub, as: ProductPubSub
  alias HydraX.Product.Requirement
  alias HydraX.Product.RequirementInsight
  alias HydraX.Product.Routine
  alias HydraX.Product.RoutineRun
  alias HydraX.Product.Source
  alias HydraX.Product.SourceChunk
  alias HydraX.Product.Strategy
  alias HydraX.Product.Task, as: ProductTask
  alias HydraX.Product.TaskFeedback
  alias HydraX.Product.WorkspaceScaffold
  alias HydraX.Repo
  alias HydraX.Runtime
  alias HydraX.Runtime.AgentProfile
  alias HydraX.Runtime.Conversation

  @chunk_size_words 120
  @chunk_overlap_words 30
  @default_search_limit 5
  @source_search_tool HydraX.Product.Tools.SourceSearch
  @insight_create_tool HydraX.Product.Tools.InsightCreate
  @insight_update_tool HydraX.Product.Tools.InsightUpdate
  @requirement_create_tool HydraX.Product.Tools.RequirementCreate
  @architecture_create_tool HydraX.Product.Tools.ArchitectureCreate
  @architecture_update_tool HydraX.Product.Tools.ArchitectureUpdate
  @feasibility_assess_tool HydraX.Product.Tools.FeasibilityAssess
  @dependency_check_tool HydraX.Product.Tools.DependencyCheck
  @design_create_tool HydraX.Product.Tools.DesignCreate
  @design_update_tool HydraX.Product.Tools.DesignUpdate
  @pattern_check_tool HydraX.Product.Tools.PatternCheck
  @graph_query_tool HydraX.Product.Tools.GraphQuery
  @trail_trace_tool HydraX.Product.Tools.TrailTrace
  @history_search_tool HydraX.Product.Tools.HistorySearch
  @decision_create_tool HydraX.Product.Tools.DecisionCreate
  @strategy_create_tool HydraX.Product.Tools.StrategyCreate

  @agent_preloads [:researcher_agent, :strategist_agent, :architect_agent, :designer_agent, :memory_agent]

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

  def project_counts(project_or_id) do
    project_id = project_id(project_or_id)

    %{
      sources: count_project_records(Source, project_id),
      insights: count_project_records(Insight, project_id),
      requirements: count_project_records(Requirement, project_id),
      conversations: count_project_records(ProductConversation, project_id),
      decisions: count_project_records(Decision, project_id),
      strategies: count_project_records(Strategy, project_id),
      design_nodes: count_project_records(DesignNode, project_id),
      architecture_nodes: count_project_records(ArchitectureNode, project_id),
      tasks: count_project_records(ProductTask, project_id),
      learnings: count_project_records(Learning, project_id),
      flags: count_project_records(GraphFlag, project_id)
    }
  end

  def change_project(project \\ %Project{}, attrs \\ %{}) do
    Project.changeset(project, normalize_project_attrs(attrs))
  end

  def create_project(attrs) when is_map(attrs) do
    attrs = normalize_project_attrs(attrs)

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
          Repo.preload(project, @agent_preloads)

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
    |> case do
      {:ok, project} -> {:ok, project}
      {:error, changeset} -> {:error, changeset}
    end
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

    Source
    |> where([source], source.project_id == ^project_id)
    |> maybe_filter_source_processing_status(processing_status)
    |> maybe_filter_source_type(source_type)
    |> maybe_filter_source_search(search)
    |> preload([:source_chunks])
    |> order_by([source], desc: source.inserted_at)
    |> Repo.all()
  end

  def get_source!(id) do
    Source
    |> preload([:source_chunks])
    |> Repo.get!(id)
  end

  def get_project_source!(project_or_id, id) do
    project_id = project_id(project_or_id)

    Source
    |> where([source], source.project_id == ^project_id and source.id == ^id)
    |> preload([:source_chunks])
    |> Repo.one!()
  end

  def change_source(source \\ %Source{}, attrs \\ %{}) do
    Source.changeset(source, normalize_source_attrs(attrs))
  end

  def delete_source(%Source{} = source) do
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
      source_attrs =
        attrs
        |> Map.drop(["upload"])
        |> Map.put("project_id", project.id)
        |> Map.put("source_type", parsed.source_type)
        |> Map.put("content", parsed.content)
        |> Map.put("processing_status", "processing")
        |> Map.put("metadata", parsed.metadata)

      with {:ok, source} <-
             %Source{}
             |> Source.changeset(source_attrs)
             |> Repo.insert() do
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

            {:ok, completed_source}

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

    Insight
    |> where([insight], insight.project_id == ^project_id)
    |> maybe_filter_product_record_status(status)
    |> maybe_filter_insight_search(search)
    |> preload(^insight_preloads())
    |> order_by([insight], desc: insight.updated_at)
    |> Repo.all()
  end

  def get_project_insight!(project_or_id, insight_id) do
    project_id = project_id(project_or_id)

    Insight
    |> where(
      [insight],
      insight.project_id == ^project_id and insight.id == ^parse_integer(insight_id)
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
            insight =
              %Insight{}
              |> Insight.changeset(%{
                "project_id" => project.id,
                "title" => attrs["title"],
                "body" => attrs["body"],
                "status" => attrs["status"] || "draft",
                "metadata" =>
                  Map.put(attrs["metadata"] || %{}, "evidence_chunk_ids", evidence_chunk_ids)
              })
              |> Repo.insert()
              |> case do
                {:ok, insight} -> insight
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

  def delete_insight(%Insight{} = insight) do
    insight
    |> Repo.delete()
    |> maybe_broadcast_project_record("insight.deleted")
    |> maybe_notify_propagation("insight", :deleted)
  end

  def update_insight(%Insight{} = insight, attrs) when is_map(attrs) do
    attrs = normalize_product_record_attrs(attrs)
    evidence_chunk_ids = normalize_integer_list(Map.get(attrs, "evidence_chunk_ids"))
    existing_chunk_ids = Enum.map(insight.insight_evidence || [], & &1.source_chunk_id)

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
            updated =
              insight
              |> Insight.changeset(%{
                "title" => attrs["title"] || insight.title,
                "body" => attrs["body"] || insight.body,
                "status" => attrs["status"] || insight.status,
                "metadata" =>
                  (insight.metadata || %{})
                  |> Map.merge(attrs["metadata"] || %{})
                  |> Map.put("evidence_chunk_ids", desired_chunk_ids)
              })
              |> Repo.update()
              |> case do
                {:ok, updated} -> updated
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

  def list_requirements(project_or_id, opts \\ []) do
    project_id = project_id(project_or_id)
    status = Keyword.get(opts, :status)
    grounded = Keyword.get(opts, :grounded)
    search = Keyword.get(opts, :search)

    Requirement
    |> where([requirement], requirement.project_id == ^project_id)
    |> maybe_filter_product_record_status(status)
    |> maybe_filter_requirement_grounded(grounded)
    |> maybe_filter_requirement_search(search)
    |> preload(^requirement_preloads())
    |> order_by([requirement], desc: requirement.updated_at)
    |> Repo.all()
  end

  def get_project_requirement!(project_or_id, requirement_id) do
    project_id = project_id(project_or_id)

    Requirement
    |> where(
      [requirement],
      requirement.project_id == ^project_id and requirement.id == ^parse_integer(requirement_id)
    )
    |> preload(^requirement_preloads())
    |> Repo.one!()
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
            requirement =
              %Requirement{}
              |> Requirement.changeset(%{
                "project_id" => project.id,
                "title" => attrs["title"],
                "body" => attrs["body"],
                "status" => status,
                "grounded" => grounded,
                "metadata" => Map.put(attrs["metadata"] || %{}, "insight_ids", insight_ids)
              })
              |> Repo.insert()
              |> case do
                {:ok, requirement} -> requirement
                {:error, changeset} -> Repo.rollback(changeset)
              end

            persist_requirement_insights!(requirement, insights)

            Repo.preload(requirement, requirement_preloads())
          end)
          |> unwrap_transaction()
          |> maybe_broadcast_project_record("requirement.created")
        end

      {:error, reason} ->
        {:error, requirement_error_changeset(project.id, attrs, "insight_ids", reason)}
    end
  end

  def update_requirement(%Requirement{} = requirement, attrs) when is_map(attrs) do
    attrs = normalize_product_record_attrs(attrs)
    existing_insight_ids = Enum.map(requirement.requirement_insights || [], & &1.insight_id)

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
            updated =
              requirement
              |> Requirement.changeset(%{
                "title" => attrs["title"] || requirement.title,
                "body" => attrs["body"] || requirement.body,
                "status" => status,
                "grounded" => grounded,
                "metadata" =>
                  (requirement.metadata || %{})
                  |> Map.merge(attrs["metadata"] || %{})
                  |> Map.put("insight_ids", insight_ids)
              })
              |> Repo.update()
              |> case do
                {:ok, updated} -> updated
                {:error, changeset} -> Repo.rollback(changeset)
              end

            if Map.has_key?(attrs, "insight_ids") do
              delete_requirement_insights!(updated.id)
              persist_requirement_insights!(updated, insights)
            end

            Repo.preload(updated, requirement_preloads())
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

  def delete_requirement(%Requirement{} = requirement) do
    requirement
    |> Repo.delete()
    |> maybe_broadcast_project_record("requirement.deleted")
    |> maybe_notify_propagation("requirement", :deleted)
  end

  # -------------------------------------------------------------------
  # Decisions
  # -------------------------------------------------------------------

  def list_decisions(project_or_id, opts \\ []) do
    project_id = project_id(project_or_id)
    status = Keyword.get(opts, :status)
    search = Keyword.get(opts, :search)

    Decision
    |> where([d], d.project_id == ^project_id)
    |> maybe_filter_product_record_status(status)
    |> maybe_filter_title_body_search(search)
    |> order_by([d], desc: d.updated_at)
    |> Repo.all()
  end

  def get_decision!(id), do: Repo.get!(Decision, id)

  def get_project_decision!(project_or_id, id) do
    project_id = project_id(project_or_id)

    Decision
    |> where([d], d.project_id == ^project_id and d.id == ^parse_integer(id))
    |> Repo.one!()
  end

  def create_decision(project_or_id, attrs) when is_map(attrs) do
    project_id = project_id(project_or_id)
    attrs = normalize_product_record_attrs(attrs)

    %Decision{}
    |> Decision.changeset(Map.put(attrs, "project_id", project_id))
    |> Repo.insert()
    |> maybe_broadcast_project_record("decision.created")
  end

  def update_decision(%Decision{} = decision, attrs) when is_map(attrs) do
    attrs = normalize_product_record_attrs(attrs)

    decision
    |> Decision.changeset(attrs)
    |> Repo.update()
    |> maybe_broadcast_project_record("decision.updated")
    |> maybe_notify_propagation("decision", :updated)
  end

  def delete_decision(%Decision{} = decision) do
    decision
    |> Repo.delete()
    |> maybe_broadcast_project_record("decision.deleted")
    |> maybe_notify_propagation("decision", :deleted)
  end

  # -------------------------------------------------------------------
  # Strategies
  # -------------------------------------------------------------------

  def list_strategies(project_or_id, opts \\ []) do
    project_id = project_id(project_or_id)
    status = Keyword.get(opts, :status)
    search = Keyword.get(opts, :search)

    Strategy
    |> where([s], s.project_id == ^project_id)
    |> maybe_filter_product_record_status(status)
    |> maybe_filter_title_body_search(search)
    |> order_by([s], desc: s.updated_at)
    |> Repo.all()
  end

  def get_strategy!(id), do: Repo.get!(Strategy, id)

  def get_project_strategy!(project_or_id, id) do
    project_id = project_id(project_or_id)

    Strategy
    |> where([s], s.project_id == ^project_id and s.id == ^parse_integer(id))
    |> Repo.one!()
  end

  def create_strategy(project_or_id, attrs) when is_map(attrs) do
    project_id = project_id(project_or_id)
    attrs = normalize_product_record_attrs(attrs)

    %Strategy{}
    |> Strategy.changeset(Map.put(attrs, "project_id", project_id))
    |> Repo.insert()
    |> maybe_broadcast_project_record("strategy.created")
  end

  def update_strategy(%Strategy{} = strategy, attrs) when is_map(attrs) do
    attrs = normalize_product_record_attrs(attrs)

    strategy
    |> Strategy.changeset(attrs)
    |> Repo.update()
    |> maybe_broadcast_project_record("strategy.updated")
    |> maybe_notify_propagation("strategy", :updated)
  end

  def delete_strategy(%Strategy{} = strategy) do
    strategy
    |> Repo.delete()
    |> maybe_broadcast_project_record("strategy.deleted")
    |> maybe_notify_propagation("strategy", :deleted)
  end

  # -------------------------------------------------------------------
  # Design Nodes
  # -------------------------------------------------------------------

  def list_design_nodes(project_or_id, opts \\ []) do
    project_id = project_id(project_or_id)
    status = Keyword.get(opts, :status)
    node_type = Keyword.get(opts, :node_type)
    search = Keyword.get(opts, :search)

    DesignNode
    |> where([d], d.project_id == ^project_id)
    |> maybe_filter_product_record_status(status)
    |> maybe_filter_node_type(node_type)
    |> maybe_filter_title_body_search(search)
    |> order_by([d], desc: d.updated_at)
    |> Repo.all()
  end

  def get_design_node!(id), do: Repo.get!(DesignNode, id)

  def get_project_design_node!(project_or_id, id) do
    project_id = project_id(project_or_id)

    DesignNode
    |> where([d], d.project_id == ^project_id and d.id == ^parse_integer(id))
    |> Repo.one!()
  end

  def create_design_node(project_or_id, attrs) when is_map(attrs) do
    project_id = project_id(project_or_id)
    attrs = normalize_product_record_attrs(attrs)

    %DesignNode{}
    |> DesignNode.changeset(Map.put(attrs, "project_id", project_id))
    |> Repo.insert()
    |> maybe_broadcast_project_record("design_node.created")
  end

  def update_design_node(%DesignNode{} = node, attrs) when is_map(attrs) do
    attrs = normalize_product_record_attrs(attrs)

    node
    |> DesignNode.changeset(attrs)
    |> Repo.update()
    |> maybe_broadcast_project_record("design_node.updated")
    |> maybe_notify_propagation("design_node", :updated)
  end

  def delete_design_node(%DesignNode{} = node) do
    node
    |> Repo.delete()
    |> maybe_broadcast_project_record("design_node.deleted")
    |> maybe_notify_propagation("design_node", :deleted)
  end

  # -------------------------------------------------------------------
  # Architecture Nodes
  # -------------------------------------------------------------------

  def list_architecture_nodes(project_or_id, opts \\ []) do
    project_id = project_id(project_or_id)
    status = Keyword.get(opts, :status)
    node_type = Keyword.get(opts, :node_type)
    search = Keyword.get(opts, :search)

    ArchitectureNode
    |> where([a], a.project_id == ^project_id)
    |> maybe_filter_product_record_status(status)
    |> maybe_filter_node_type(node_type)
    |> maybe_filter_title_body_search(search)
    |> order_by([a], a.updated_at)
    |> Repo.all()
  end

  def get_architecture_node!(id), do: Repo.get!(ArchitectureNode, id)

  def get_project_architecture_node!(project_or_id, id) do
    project_id = project_id(project_or_id)

    ArchitectureNode
    |> where([a], a.project_id == ^project_id and a.id == ^parse_integer(id))
    |> Repo.one!()
  end

  def create_architecture_node(project_or_id, attrs) when is_map(attrs) do
    project_id = project_id(project_or_id)
    attrs = normalize_product_record_attrs(attrs)

    %ArchitectureNode{}
    |> ArchitectureNode.changeset(Map.put(attrs, "project_id", project_id))
    |> Repo.insert()
    |> maybe_broadcast_project_record("architecture_node.created")
  end

  def update_architecture_node(%ArchitectureNode{} = node, attrs) when is_map(attrs) do
    attrs = normalize_product_record_attrs(attrs)

    node
    |> ArchitectureNode.changeset(attrs)
    |> Repo.update()
    |> maybe_broadcast_project_record("architecture_node.updated")
    |> maybe_notify_propagation("architecture_node", :updated)
  end

  def delete_architecture_node(%ArchitectureNode{} = node) do
    node
    |> Repo.delete()
    |> maybe_broadcast_project_record("architecture_node.deleted")
    |> maybe_notify_propagation("architecture_node", :deleted)
  end

  # -------------------------------------------------------------------
  # Tasks
  # -------------------------------------------------------------------

  def list_tasks(project_or_id, opts \\ []) do
    project_id = project_id(project_or_id)
    status = Keyword.get(opts, :status)
    priority = Keyword.get(opts, :priority)
    search = Keyword.get(opts, :search)

    ProductTask
    |> where([t], t.project_id == ^project_id)
    |> maybe_filter_product_record_status(status)
    |> maybe_filter_priority(priority)
    |> maybe_filter_title_body_search(search)
    |> order_by([t], desc: t.updated_at)
    |> Repo.all()
  end

  def get_task!(id), do: Repo.get!(ProductTask, id)

  def get_project_task!(project_or_id, id) do
    project_id = project_id(project_or_id)

    ProductTask
    |> where([t], t.project_id == ^project_id and t.id == ^parse_integer(id))
    |> Repo.one!()
  end

  def create_task(project_or_id, attrs) when is_map(attrs) do
    project_id = project_id(project_or_id)
    attrs = normalize_product_record_attrs(attrs)

    %ProductTask{}
    |> ProductTask.changeset(Map.put(attrs, "project_id", project_id))
    |> Repo.insert()
    |> maybe_broadcast_project_record("task.created")
  end

  def update_task(%ProductTask{} = task, attrs) when is_map(attrs) do
    attrs = normalize_product_record_attrs(attrs)

    task
    |> ProductTask.changeset(attrs)
    |> Repo.update()
    |> maybe_broadcast_project_record("task.updated")
    |> maybe_notify_propagation("task", :updated)
  end

  def delete_task(%ProductTask{} = task) do
    task
    |> Repo.delete()
    |> maybe_broadcast_project_record("task.deleted")
    |> maybe_notify_propagation("task", :deleted)
  end

  # -------------------------------------------------------------------
  # Learnings
  # -------------------------------------------------------------------

  def list_learnings(project_or_id, opts \\ []) do
    project_id = project_id(project_or_id)
    status = Keyword.get(opts, :status)
    learning_type = Keyword.get(opts, :learning_type)
    search = Keyword.get(opts, :search)

    Learning
    |> where([l], l.project_id == ^project_id)
    |> maybe_filter_product_record_status(status)
    |> maybe_filter_learning_type(learning_type)
    |> maybe_filter_title_body_search(search)
    |> order_by([l], desc: l.updated_at)
    |> Repo.all()
  end

  def get_learning!(id), do: Repo.get!(Learning, id)

  def get_project_learning!(project_or_id, id) do
    project_id = project_id(project_or_id)

    Learning
    |> where([l], l.project_id == ^project_id and l.id == ^parse_integer(id))
    |> Repo.one!()
  end

  def create_learning(project_or_id, attrs) when is_map(attrs) do
    project_id = project_id(project_or_id)
    attrs = normalize_product_record_attrs(attrs)

    %Learning{}
    |> Learning.changeset(Map.put(attrs, "project_id", project_id))
    |> Repo.insert()
    |> maybe_broadcast_project_record("learning.created")
  end

  def update_learning(%Learning{} = learning, attrs) when is_map(attrs) do
    attrs = normalize_product_record_attrs(attrs)

    learning
    |> Learning.changeset(attrs)
    |> Repo.update()
    |> maybe_broadcast_project_record("learning.updated")
    |> maybe_notify_propagation("learning", :updated)
  end

  def delete_learning(%Learning{} = learning) do
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

    GraphEdge
    |> where([e], e.project_id == ^project_id)
    |> maybe_filter_edge_kind(kind)
    |> maybe_filter_edge_node_type(node_type)
    |> order_by([e], desc: e.inserted_at)
    |> Repo.all()
  end

  def get_graph_edge!(id), do: Repo.get!(GraphEdge, id)

  def create_graph_edge(attrs) when is_map(attrs) do
    attrs = HydraX.Runtime.Helpers.normalize_string_keys(attrs)

    %GraphEdge{}
    |> GraphEdge.changeset(attrs)
    |> Repo.insert()
  end

  def delete_graph_edge(%GraphEdge{} = edge) do
    Repo.delete(edge)
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

    Constraint
    |> where([c], c.project_id == ^project_id)
    |> maybe_filter_product_record_status(status)
    |> order_by([c], desc: c.updated_at)
    |> Repo.all()
  end

  def get_constraint!(id), do: Repo.get!(Constraint, id)

  def get_project_constraint!(project_or_id, id) do
    project_id = project_id(project_or_id)
    Constraint |> where([c], c.project_id == ^project_id and c.id == ^parse_integer(id)) |> Repo.one!()
  end

  def create_constraint(project_or_id, attrs) when is_map(attrs) do
    project_id = project_id(project_or_id)
    attrs = normalize_product_record_attrs(attrs)

    %Constraint{}
    |> Constraint.changeset(Map.put(attrs, "project_id", project_id))
    |> Repo.insert()
    |> maybe_broadcast_project_record("constraint.created")
  end

  def update_constraint(%Constraint{} = constraint, attrs) when is_map(attrs) do
    attrs = normalize_product_record_attrs(attrs)

    constraint
    |> Constraint.changeset(attrs)
    |> Repo.update()
    |> maybe_broadcast_project_record("constraint.updated")
  end

  def delete_constraint(%Constraint{} = constraint) do
    constraint |> Repo.delete() |> maybe_broadcast_project_record("constraint.deleted")
  end

  # -------------------------------------------------------------------
  # Routines
  # -------------------------------------------------------------------

  def list_routines(project_or_id, opts \\ []) do
    project_id = project_id(project_or_id)
    status = Keyword.get(opts, :status)

    Routine
    |> where([r], r.project_id == ^project_id)
    |> maybe_filter_product_record_status(status)
    |> order_by([r], desc: r.updated_at)
    |> Repo.all()
  end

  def get_routine!(id), do: Repo.get!(Routine, id)

  def get_project_routine!(project_or_id, id) do
    project_id = project_id(project_or_id)
    Routine |> where([r], r.project_id == ^project_id and r.id == ^parse_integer(id)) |> Repo.one!()
  end

  def create_routine(project_or_id, attrs) when is_map(attrs) do
    project_id = project_id(project_or_id)
    attrs = normalize_product_record_attrs(attrs)

    %Routine{}
    |> Routine.changeset(Map.put(attrs, "project_id", project_id))
    |> Repo.insert()
  end

  def update_routine(%Routine{} = routine, attrs) when is_map(attrs) do
    attrs = normalize_product_record_attrs(attrs)
    routine |> Routine.changeset(attrs) |> Repo.update()
  end

  def delete_routine(%Routine{} = routine), do: Repo.delete(routine)

  def list_routine_runs(routine_or_id, opts \\ []) do
    routine_id = case routine_or_id do
      %Routine{id: id} -> id
      id -> parse_integer(id)
    end
    limit = Keyword.get(opts, :limit, 20)

    RoutineRun
    |> where([r], r.routine_id == ^routine_id)
    |> order_by([r], desc: r.started_at)
    |> limit(^limit)
    |> Repo.all()
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
      KnowledgeEntry
      |> where([k], k.project_id == ^project_id)
      |> maybe_filter_product_record_status(status)

    query =
      if persona,
        do: where(query, [k], ^to_string(persona) in k.assigned_personas),
        else: query

    query |> order_by([k], desc: k.updated_at) |> Repo.all()
  end

  def get_knowledge_entry!(id), do: Repo.get!(KnowledgeEntry, id)

  def get_project_knowledge_entry!(project_or_id, id) do
    project_id = project_id(project_or_id)
    KnowledgeEntry |> where([k], k.project_id == ^project_id and k.id == ^parse_integer(id)) |> Repo.one!()
  end

  def create_knowledge_entry(project_or_id, attrs) when is_map(attrs) do
    project_id = project_id(project_or_id)
    attrs = normalize_product_record_attrs(attrs)

    %KnowledgeEntry{}
    |> KnowledgeEntry.changeset(Map.put(attrs, "project_id", project_id))
    |> Repo.insert()
  end

  def update_knowledge_entry(%KnowledgeEntry{} = entry, attrs) when is_map(attrs) do
    attrs = normalize_product_record_attrs(attrs)
    entry |> KnowledgeEntry.changeset(attrs) |> Repo.update()
  end

  def delete_knowledge_entry(%KnowledgeEntry{} = entry), do: Repo.delete(entry)

  # -------------------------------------------------------------------
  # Task Feedback
  # -------------------------------------------------------------------

  def list_task_feedback(task_or_id) do
    task_id = case task_or_id do
      %{id: id} -> id
      id -> parse_integer(id)
    end

    TaskFeedback
    |> where([f], f.task_id == ^task_id)
    |> order_by([f], desc: f.inserted_at)
    |> Repo.all()
  end

  def create_task_feedback(task_or_id, attrs) when is_map(attrs) do
    task_id = case task_or_id do
      %{id: id} -> id
      id -> parse_integer(id)
    end
    attrs = HydraX.Runtime.Helpers.normalize_string_keys(attrs)

    %TaskFeedback{}
    |> TaskFeedback.changeset(Map.put(attrs, "task_id", task_id))
    |> Repo.insert()
  end

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

    knowledge = list_knowledge_entries(project.id, persona: persona)

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
    """
  end

  defp persona_prompt_context(project_id, "strategist") do
    """
    Active insights: #{count_active_nodes(project_id, Insight)}
    Active decisions: #{count_active_nodes(project_id, Decision)}
    When creating requirements, always link to supporting insights.
    When making decisions, record them with decision_create including alternatives considered.
    """
  end

  defp persona_prompt_context(project_id, "architect") do
    """
    Active requirements: #{count_active_nodes(project_id, Requirement)}
    Architecture nodes: #{count_active_nodes(project_id, ArchitectureNode)}
    Always link architecture decisions to the requirements they serve.
    """
  end

  defp persona_prompt_context(project_id, "designer") do
    """
    Active requirements: #{count_active_nodes(project_id, Requirement)}
    Design nodes: #{count_active_nodes(project_id, DesignNode)}
    Check pattern_check before creating new interaction patterns.
    """
  end

  defp persona_prompt_context(project_id, "memory_agent") do
    """
    You have read-only access to the product graph. You NEVER create or modify nodes.
    Graph summary:
    - Insights: #{count_active_nodes(project_id, Insight)}
    - Decisions: #{count_active_nodes(project_id, Decision)}
    - Strategies: #{count_active_nodes(project_id, Strategy)}
    - Requirements: #{count_active_nodes(project_id, Requirement)}
    - Architecture nodes: #{count_active_nodes(project_id, ArchitectureNode)}
    - Design nodes: #{count_active_nodes(project_id, DesignNode)}
    Use graph_query and trail_trace to find information. Cite specific nodes in your answers.
    """
  end

  defp persona_prompt_context(_project_id, _persona), do: ""

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
    [@source_search_tool, @insight_create_tool, @insight_update_tool]
  end

  defp tools_for_persona("strategist") do
    [
      @source_search_tool,
      @insight_create_tool,
      @insight_update_tool,
      @requirement_create_tool,
      @decision_create_tool,
      @strategy_create_tool
    ]
  end

  defp tools_for_persona("architect") do
    [
      @source_search_tool,
      @architecture_create_tool,
      @architecture_update_tool,
      @feasibility_assess_tool,
      @requirement_create_tool
    ]
  end

  defp tools_for_persona("designer") do
    [
      @source_search_tool,
      @design_create_tool,
      @design_update_tool,
      @pattern_check_tool,
      @insight_create_tool
    ]
  end

  defp tools_for_persona("memory_agent") do
    [@source_search_tool, @graph_query_tool, @trail_trace_tool]
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

  def get_product_conversation!(project_or_id, conversation_id) do
    project_id = project_id(project_or_id)

    ProductConversation
    |> where(
      [conversation],
      conversation.project_id == ^project_id and
        conversation.id == ^parse_integer(conversation_id)
    )
    |> preload(^product_conversation_preloads())
    |> Repo.one!()
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
    attrs =
      attrs
      |> Map.drop(["upload"])
      |> Map.put("project_id", project.id)

    %Source{}
    |> Source.changeset(attrs)
    |> Ecto.Changeset.add_error(:content, source_error_message(reason))
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
      requirement_insights: [insight: [insight_evidence: [source_chunk: [:source]]]]
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
    where(query, [source], source.processing_status == ^to_string(status))
  end

  defp maybe_filter_source_type(query, nil), do: query
  defp maybe_filter_source_type(query, ""), do: query

  defp maybe_filter_source_type(query, source_type) do
    where(query, [source], source.source_type == ^to_string(source_type))
  end

  defp maybe_filter_source_search(query, nil), do: query
  defp maybe_filter_source_search(query, ""), do: query

  defp maybe_filter_source_search(query, search) do
    term = "%#{String.trim(to_string(search))}%"

    where(
      query,
      [source],
      ilike(source.title, ^term) or ilike(source.content, ^term) or
        ilike(source.external_ref, ^term)
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

  defp maybe_filter_priority(query, nil), do: query
  defp maybe_filter_priority(query, ""), do: query

  defp maybe_filter_priority(query, priority) do
    where(query, [r], r.priority == ^to_string(priority))
  end

  defp maybe_filter_learning_type(query, nil), do: query
  defp maybe_filter_learning_type(query, ""), do: query

  defp maybe_filter_learning_type(query, learning_type) do
    where(query, [r], r.learning_type == ^to_string(learning_type))
  end

  defp maybe_filter_edge_kind(query, nil), do: query
  defp maybe_filter_edge_kind(query, ""), do: query

  defp maybe_filter_edge_kind(query, kind) do
    where(query, [e], e.kind == ^to_string(kind))
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
      nil -> query
      value -> where(query, [requirement], requirement.grounded == ^value)
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
      Insight
      |> where([insight], insight.project_id == ^project_id and insight.id in ^insight_ids)
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
    (insight.insight_evidence || []) != []
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
    %Insight{}
    |> Insight.changeset(%{
      "project_id" => project_id,
      "title" => attrs["title"],
      "body" => attrs["body"],
      "status" => attrs["status"] || "draft",
      "metadata" => attrs["metadata"] || %{}
    })
    |> Ecto.Changeset.add_error(product_error_field(field), message)
  end

  defp requirement_error_changeset(project_id, attrs, field, message) do
    %Requirement{}
    |> Requirement.changeset(%{
      "project_id" => project_id,
      "title" => attrs["title"],
      "body" => attrs["body"],
      "status" => attrs["status"] || "draft",
      "grounded" => false,
      "metadata" => attrs["metadata"] || %{}
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

      source
      |> Source.changeset(%{
        "processing_status" => "completed",
        "metadata" =>
          Map.merge(parsed.metadata, %{
            "chunk_count" => length(chunks),
            "word_count" => word_count(parsed.content)
          })
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
    source
    |> Source.changeset(%{
      "metadata" => Map.put(source.metadata || %{}, "memory_mirror", mirror_state)
    })
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
      "product_source_type" => source.source_type,
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
    source
    |> Source.changeset(%{
      "processing_status" => "failed",
      "metadata" => Map.put(source.metadata || %{}, "last_error", "source ingestion failed")
    })
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
      %{chunk: chunk, lexical_score: Map.get(lexical_scores, chunk.id, 0.0)}
    end)
  end

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
    %{
      id: source.id,
      project_id: source.project_id,
      title: source.title,
      source_type: source.source_type,
      content: source.content,
      external_ref: source.external_ref,
      processing_status: source.processing_status,
      metadata: source.metadata || %{},
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
      metadata: insight.metadata || %{},
      evidence:
        Enum.map(insight.insight_evidence || [], fn evidence ->
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
      requirement_ids: Enum.map(insight.requirement_insights || [], & &1.requirement_id),
      inserted_at: insight.inserted_at,
      updated_at: insight.updated_at
    }
  end

  defp requirement_export_json(requirement) do
    %{
      id: requirement.id,
      project_id: requirement.project_id,
      title: requirement.title,
      body: requirement.body,
      status: requirement.status,
      grounded: requirement.grounded,
      metadata: requirement.metadata || %{},
      insights:
        Enum.map(requirement.requirement_insights || [], fn link ->
          insight = link.insight

          %{
            id: insight.id,
            title: insight.title,
            status: insight.status,
            evidence_chunk_ids: Enum.map(insight.insight_evidence || [], & &1.source_chunk_id)
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
      [
        "- [#{source.id}] #{source.title} (#{source.source_type}) chunks=#{length(source.source_chunks)} status=#{source.processing_status}"
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
        "- [#{requirement.id}] #{requirement.title} status=#{requirement.status} grounded=#{if(requirement.grounded, do: "yes", else: "no")} insights=#{length(requirement.insights)}",
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
