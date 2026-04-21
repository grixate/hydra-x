defmodule HydraX.Product.Mention do
  @moduledoc """
  An @-reference between agents or from a user to an agent. Spec §5 of the
  task-data-model.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @source_types ~w(task chat_message proposal_review)
  @intents ~w(request_task share_context request_input notify)

  schema "mentions" do
    field :source_type, :string
    field :source_message_id, :integer
    field :source_agent_id, :string
    field :source_user_id, :integer
    field :target_agent_id, :string
    field :content, :string
    field :intent, :string, default: "share_context"
    field :metadata, :map, default: %{}

    belongs_to :project, HydraX.Product.Project
    belongs_to :source_task, HydraX.Product.AgentTask, foreign_key: :source_task_id
    belongs_to :target_task, HydraX.Product.AgentTask, foreign_key: :target_task_id

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def source_types, do: @source_types
  def intents, do: @intents

  def changeset(mention, attrs) do
    mention
    |> cast(attrs, [
      :project_id,
      :source_type,
      :source_task_id,
      :source_message_id,
      :source_agent_id,
      :source_user_id,
      :target_agent_id,
      :target_task_id,
      :content,
      :intent,
      :metadata
    ])
    |> validate_required([:project_id, :source_type, :target_agent_id, :intent])
    |> validate_inclusion(:source_type, @source_types)
    |> validate_inclusion(:intent, @intents)
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:source_task_id)
    |> foreign_key_constraint(:target_task_id)
  end
end
