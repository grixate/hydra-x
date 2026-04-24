defmodule HydraX.Graph.Domains.ProductDevelopment do
  @moduledoc """
  Seed for the built-in `product_development` domain. Idempotent —
  running it multiple times upserts the same definitions.

  Only the core epistemic types in the §7 mapping are included here.
  Learnings, KnowledgeEntry, Task, Routine, the Board subsystem, and
  the Flow/Proposal subsystems are deliberately deferred until we
  agree which of them belong in the substrate vs. stay separate.

  Invoke via `HydraX.Graph.Domains.ProductDevelopment.seed/0` (e.g. from
  a mix task, test setup, or the main seeds.exs).
  """

  alias HydraX.Graph.Domains

  @slug "product_development"
  @version "0.1.0"

  def slug, do: @slug

  def seed do
    {:ok, domain} =
      Domains.upsert_domain(%{
        slug: @slug,
        name: "Product Development",
        version: @version,
        status: "active",
        source: "builtin",
        metadata: %{
          "description" => "The built-in domain for Hydra product-development work."
        }
      })

    Enum.each(node_types(), fn attrs ->
      {:ok, _} = Domains.upsert_node_type(domain, attrs)
    end)

    Enum.each(relationship_types(), fn attrs ->
      {:ok, _} = Domains.upsert_relationship_type(domain, attrs)
    end)

    Enum.each(flag_types(), fn attrs ->
      {:ok, _} = Domains.upsert_flag_type(domain, attrs)
    end)

    {:ok, domain}
  end

  # §7 mapping (core 10). Status vocabularies are explicit where the current
  # schemas have something richer than the primitive default.

  defp node_types do
    [
      %{
        type_key: "insight",
        display_name: "Insight",
        description: "An assertion about the world grounded in evidence.",
        extends: "claim",
        status_vocabulary: ~w(draft accepted rejected),
        attribute_schema: %{
          "type" => "object",
          "properties" => %{
            "summary" => %{"type" => "string"},
            "evidence_strength" => %{
              "type" => "string",
              "enum" => ["weak", "moderate", "strong"]
            },
            "origin_context" => %{"type" => "string"},
            "evidence_chunk_ids" => %{"type" => "array"}
          }
        },
        icon: "hero-light-bulb",
        color_token: "--color-accent-amber"
      },
      %{
        type_key: "decision",
        display_name: "Decision",
        description: "A committed choice that shapes downstream work.",
        extends: "claim",
        status_vocabulary: ~w(draft active superseded archived),
        attribute_schema: %{
          "type" => "object",
          "properties" => %{
            "rationale" => %{"type" => "string"},
            "alternatives_considered" => %{"type" => "array"},
            "reversibility" => %{
              "type" => "string",
              "enum" => ["one_way", "two_way"]
            },
            "decided_by" => %{"type" => "string"},
            "decided_at" => %{"type" => "string"}
          }
        },
        icon: "hero-check-badge",
        color_token: "--color-accent-violet"
      },
      %{
        type_key: "requirement",
        display_name: "Requirement",
        description: "A thing that should exist or hold in the product.",
        extends: "entity",
        status_vocabulary: ~w(draft accepted rejected),
        attribute_schema: %{
          "type" => "object",
          "properties" => %{
            "grounded" => %{"type" => "boolean"},
            "priority" => %{
              "type" => "string",
              "enum" => ["low", "medium", "high", "critical"]
            },
            "acceptance_criteria" => %{"type" => "array"},
            "insight_ids" => %{"type" => "array"}
          }
        },
        icon: "hero-clipboard-document-check",
        color_token: "--color-accent-sky"
      },
      %{
        type_key: "strategy",
        display_name: "Strategy",
        description: "A high-level posture or direction; a claim about how to act.",
        extends: "claim",
        status_vocabulary: ~w(draft active superseded archived),
        attribute_schema: %{
          "type" => "object",
          "properties" => %{
            "horizon" => %{"type" => "string"},
            "reach" => %{"type" => "string"},
            "assumptions" => %{"type" => "array"}
          }
        },
        icon: "hero-map",
        color_token: "--color-accent-indigo"
      },
      %{
        type_key: "constraint",
        display_name: "Constraint",
        description: "A boundary condition the product must respect.",
        extends: "claim",
        status_vocabulary: ~w(active suspended archived),
        attribute_schema: %{
          "type" => "object",
          "properties" => %{
            "reach_scope" => %{
              "type" => "string",
              "enum" => ["global", "technical", "design", "process", "business"]
            },
            "enforcement" => %{
              "type" => "string",
              "enum" => ["strict", "advisory"]
            }
          }
        },
        icon: "hero-lock-closed",
        color_token: "--color-accent-rose"
      },
      %{
        type_key: "design_node",
        display_name: "Design Node",
        description: "A design deliverable (wireframe, component, flow).",
        extends: "artifact",
        status_vocabulary: ~w(draft active superseded archived),
        attribute_schema: %{
          "type" => "object",
          "properties" => %{
            "node_type" => %{
              "type" => "string",
              "enum" =>
                ~w(user_flow wireframe interaction_pattern component_spec design_rationale)
            },
            "fidelity" => %{"type" => "string"},
            "linked_requirements" => %{"type" => "array"}
          }
        },
        icon: "hero-swatch",
        color_token: "--color-accent-fuchsia"
      },
      %{
        type_key: "architecture_node",
        display_name: "Architecture Node",
        description: "A structural artifact describing how the system is organised.",
        extends: "artifact",
        status_vocabulary: ~w(draft active superseded archived),
        attribute_schema: %{
          "type" => "object",
          "properties" => %{
            "node_type" => %{
              "type" => "string",
              "enum" => ~w(system_design data_model api_contract infra_choice tech_selection)
            },
            "layer" => %{"type" => "string"},
            "technology" => %{"type" => "string"}
          }
        },
        icon: "hero-cube-transparent",
        color_token: "--color-accent-emerald"
      },
      %{
        type_key: "artifact",
        display_name: "Artifact",
        description: "A versioned produced deliverable.",
        extends: "artifact",
        status_vocabulary: ~w(active archived),
        attribute_schema: %{
          "type" => "object",
          "properties" => %{
            "artifact_type" => %{
              "type" => "string",
              "enum" =>
                ~w(competitive_analysis strategy_memo project_summary decision_log design_language spec campaign report reference brief custom)
            },
            "owner_persona" => %{"type" => "string"},
            "last_updated_by" => %{"type" => "string"}
          }
        },
        icon: "hero-document",
        color_token: "--color-accent-stone"
      },
      %{
        type_key: "source",
        display_name: "Source",
        description: "A grounded piece of evidence — a document, web page, citation.",
        extends: "evidence",
        status_vocabulary: ~w(pending processing completed failed),
        attribute_schema: %{
          "type" => "object",
          "properties" => %{
            "source_type" => %{"type" => "string"},
            "external_ref" => %{"type" => "string"},
            "reviewed_at" => %{"type" => "string"},
            "promoted_to_graph" => %{"type" => "boolean"},
            "promoted_at" => %{"type" => "string"}
          }
        },
        icon: "hero-book-open",
        color_token: "--color-accent-teal"
      },
      %{
        type_key: "agent_task",
        display_name: "Agent Task",
        description: "A unit of agent work, with state, progress, and proposal payload.",
        extends: "activity",
        status_vocabulary:
          ~w(pending running paused waiting_for_input blocked proposing completed rejected cancelled failed),
        attribute_schema: %{
          "type" => "object",
          "properties" => %{
            "agent_id" => %{"type" => "string"},
            "proposal_payload" => %{"type" => "object"},
            "progress_current" => %{"type" => "integer"},
            "progress_total" => %{"type" => "integer"}
          }
        },
        icon: "hero-bolt",
        color_token: "--color-accent-yellow"
      },
      %{
        type_key: "task",
        display_name: "Task",
        description: "A human-assigned unit of work.",
        extends: "activity",
        status_vocabulary: ~w(backlog ready in_progress review done archived),
        attribute_schema: %{
          "type" => "object",
          "properties" => %{
            "assignee" => %{"type" => "string"},
            "effort_estimate" => %{"type" => "string"},
            "priority" => %{
              "type" => "string",
              "enum" => ["critical", "high", "medium", "low"]
            }
          }
        },
        icon: "hero-clipboard-document-list",
        color_token: "--color-accent-blue"
      },
      %{
        type_key: "learning",
        display_name: "Learning",
        description: "Retrospective or data-grounded claim about what was learned.",
        extends: "claim",
        status_vocabulary: ~w(draft active archived),
        attribute_schema: %{
          "type" => "object",
          "properties" => %{
            "learning_type" => %{
              "type" => "string",
              "enum" =>
                ~w(retrospective post_mortem usage_data experiment_result)
            }
          }
        },
        icon: "hero-academic-cap",
        color_token: "--color-accent-lime"
      },
      %{
        type_key: "knowledge_entry",
        display_name: "Knowledge Entry",
        description: "A reference piece of project knowledge (design system, conventions, domain docs).",
        extends: "evidence",
        status_vocabulary: ~w(active pending_review archived),
        attribute_schema: %{
          "type" => "object",
          "properties" => %{
            "entry_type" => %{
              "type" => "string",
              "enum" =>
                ~w(design_language coding_conventions brand_guide product_vision domain_knowledge process_rules integration_docs pattern custom)
            },
            "assigned_personas" => %{"type" => "array"},
            "source_type" => %{
              "type" => "string",
              "enum" => ["manual", "url", "generated"]
            },
            "source_url" => %{"type" => "string"}
          }
        },
        icon: "hero-book-open",
        color_token: "--color-accent-cyan"
      },
      %{
        type_key: "routine",
        display_name: "Routine",
        description: "Scheduled recurring agent task (cron or event-triggered).",
        extends: "activity",
        status_vocabulary: ~w(active paused archived),
        attribute_schema: %{
          "type" => "object",
          "properties" => %{
            "prompt_template" => %{"type" => "string"},
            "assigned_persona" => %{"type" => "string"},
            "schedule_type" => %{
              "type" => "string",
              "enum" => ["cron", "event"]
            },
            "cron_expression" => %{"type" => "string"},
            "event_trigger" => %{"type" => "string"},
            "timezone" => %{"type" => "string"},
            "output_target" => %{
              "type" => "string",
              "enum" => ["graph_node", "stream_item"]
            },
            "last_run_at" => %{"type" => "string"},
            "last_run_status" => %{"type" => "string"},
            "last_run_tokens" => %{"type" => "integer"}
          }
        },
        icon: "hero-arrow-path",
        color_token: "--color-accent-slate"
      },
      %{
        type_key: "vision",
        display_name: "Vision",
        description: "The root node of a project: why it exists. At most one per project.",
        extends: "claim",
        status_vocabulary: ~w(active archived superseded),
        attribute_schema: %{
          "type" => "object",
          "properties" => %{
            "horizon" => %{"type" => "string"},
            "north_star" => %{"type" => "string"}
          }
        },
        icon: "hero-flag",
        color_token: "--color-accent-gold"
      }
    ]
  end

  defp relationship_types do
    [
      %{
        type_key: "supports",
        display_name: "Supports",
        description: "Evidence or claim positively supports another claim.",
        extends: "supports"
      },
      %{
        type_key: "contradicts",
        display_name: "Contradicts",
        description: "Evidence or claim negatively relates to another claim.",
        extends: "contradicts"
      },
      %{
        type_key: "supersedes",
        display_name: "Supersedes",
        description: "A claim replaces another as current understanding.",
        extends: "supersedes",
        cardinality: "many_to_many"
      },
      %{
        type_key: "lineage",
        display_name: "Lineage",
        description: "General provenance — derived from.",
        extends: "derives_from"
      },
      %{
        type_key: "dependency",
        display_name: "Dependency",
        description: "One activity or entity depends on another.",
        extends: "depends_on"
      },
      %{
        type_key: "blocks",
        display_name: "Blocks",
        description: "One node cannot proceed while another is unresolved.",
        extends: "depends_on"
      },
      %{
        type_key: "enables",
        display_name: "Enables",
        description: "One node makes another viable or reachable.",
        extends: "supports"
      },
      %{
        type_key: "constrains",
        display_name: "Constrains",
        description: "A constraint binds the shape of another node.",
        extends: "contradicts"
      }
    ]
  end

  defp flag_types do
    [
      %{
        type_key: "orphaned",
        display_name: "Orphaned",
        description: "Node has no inbound or outbound relationships.",
        default_severity: "warning"
      },
      %{
        type_key: "stale",
        display_name: "Stale",
        description: "Node has had no updates for too long given open related work.",
        default_severity: "info"
      },
      %{
        type_key: "contradicted",
        display_name: "Contradicted",
        description: "A claim has incoming `contradicts` relationships.",
        default_severity: "critical"
      },
      %{
        type_key: "needs_review",
        display_name: "Needs Review",
        description: "An operator needs to review this node.",
        default_severity: "warning"
      },
      %{
        type_key: "confidence_decayed",
        display_name: "Confidence Decayed",
        description: "A claim's confidence has dropped below its threshold.",
        default_severity: "warning"
      }
    ]
  end
end
