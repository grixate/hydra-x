defmodule HydraX.Graph.Primitives do
  @moduledoc """
  Domain-neutral vocabulary the epistemic engine keys off. Domain-specific
  node and relationship types declare an `extends` primitive to inherit
  cross-cutting behaviours (contradiction detection, lineage traversal,
  supersession, orphan/stale flagging, stream emission).

  See `docs/specs/hydra-domain-extensibility-part-1-schema-substrate.md` §6.
  """

  @node_primitives ~w(claim evidence artifact activity entity agent_role)
  @relationship_primitives ~w(
    supports
    contradicts
    supersedes
    derives_from
    references
    depends_on
    produces
    measures
  )

  @default_status_vocabularies %{
    "claim" => ~w(proposed active superseded retracted),
    "evidence" => ~w(candidate confirmed archived disputed),
    "artifact" => ~w(draft published archived),
    "activity" => ~w(pending running completed failed cancelled),
    "entity" => ~w(draft active archived),
    "agent_role" => ~w(active inactive)
  }

  def node_primitives, do: @node_primitives
  def relationship_primitives, do: @relationship_primitives

  def node_primitive?(value), do: value in @node_primitives
  def relationship_primitive?(value), do: value in @relationship_primitives

  def default_status_vocabulary(primitive) when is_binary(primitive) do
    Map.get(@default_status_vocabularies, primitive, [])
  end
end
