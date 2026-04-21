defmodule HydraX.Product.AgentRule do
  use Ecto.Schema
  import Ecto.Changeset

  @rule_types ~w(mute_category ignore_pattern prioritize_category)
  @agent_ids ~w(coherence continuous_research)

  schema "agent_rules" do
    field :agent_id, :string
    field :rule_type, :string
    field :value, :string

    belongs_to :project, HydraX.Product.Project

    timestamps()
  end

  def changeset(rule, attrs) do
    rule
    |> cast(attrs, [:project_id, :agent_id, :rule_type, :value])
    |> validate_required([:project_id, :agent_id, :rule_type, :value])
    |> validate_inclusion(:agent_id, @agent_ids)
    |> validate_inclusion(:rule_type, @rule_types)
    |> unique_constraint([:project_id, :agent_id, :rule_type, :value])
    |> foreign_key_constraint(:project_id)
  end

  def rule_types, do: @rule_types
  def agent_ids, do: @agent_ids
end
