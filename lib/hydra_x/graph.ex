defmodule HydraX.Graph do
  @moduledoc """
  The domain-neutral substrate context. Owns `Node`, `NodeRelationship`,
  `NodeFlag`, and the schema-definition tables (`Domain`,
  `NodeTypeDefinition`, `RelationshipTypeDefinition`,
  `FlagTypeDefinition`).

  Phase 1a ships the schemas and migration only. Subsequent phases add:
    * `SchemaRegistry` — cached schema lookup + attribute validation.
    * `Primitives`-keyed traversal and coherence.
    * Schema-change proposal lifecycle.
    * Adapters from the existing typed product context.
  """

  alias HydraX.Graph.Domain
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
          Domain
          | NodeTypeDefinition
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
