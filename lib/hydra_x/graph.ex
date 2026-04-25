defmodule HydraX.Graph do
  @moduledoc """
  The substrate context. Owns `Node`, `NodeRelationship`, `NodeFlag`,
  and the schema-definition tables (`NodeTypeDefinition`,
  `RelationshipTypeDefinition`, `FlagTypeDefinition`).

  Per the Part 1 amendment, the substrate is project-scoped — there
  is no longer a `domain` layer above projects. Schemas live with
  projects; pretrained projects (lib/hydra_x/pretrained_projects/)
  populate them at apply time.

  Composition:
    * `SchemaRegistry` — cached schema lookup + attribute validation
      keyed by project_id.
    * `Primitives` — base epistemic vocabulary (claim/evidence/etc.).
    * `ProjectSchemas` — project-scoped CRUD for type definitions.
    * `Proposals` — schema-change proposal lifecycle.
  """

  alias HydraX.Graph.FlagTypeDefinition
  alias HydraX.Graph.Node
  alias HydraX.Graph.NodeEmbedding
  alias HydraX.Graph.NodeFlag
  alias HydraX.Graph.NodeRelationship
  alias HydraX.Graph.NodeTypeDefinition
  alias HydraX.Graph.Primitives
  alias HydraX.Graph.RelationshipTypeDefinition
  alias HydraX.Graph.SchemaChangeProposal

  @type schema_module ::
          NodeTypeDefinition
          | RelationshipTypeDefinition
          | FlagTypeDefinition
          | Node
          | NodeRelationship
          | NodeFlag
          | NodeEmbedding
          | SchemaChangeProposal

  @doc false
  def primitives, do: Primitives
end
