defmodule HydraX.Runtime.WorkItem do
  use Ecto.Schema
  import Ecto.Changeset

  alias HydraX.Runtime.Autonomy

  @statuses ~w(planned claimed running blocked completed failed canceled replayed)
  @kinds ~w(task research engineering extension review plan design trading)
  @execution_modes ~w(execute delegate review promote)
  @approval_stages ~w(draft proposal_only patch_ready validated operator_approved merge_ready)

  schema "work_items" do
    field :kind, :string, default: "task"
    field :goal, :string
    field :status, :string, default: "planned"
    field :execution_mode, :string, default: "execute"
    field :assigned_role, :string, default: "operator"
    field :priority, :integer, default: 0
    field :autonomy_level, :string, default: "recommend"
    field :review_required, :boolean, default: true
    field :approval_stage, :string, default: "draft"
    field :deadline_at, :utc_datetime_usec
    field :budget, :map, default: %{}
    field :input_artifact_refs, :map, default: %{}
    field :required_outputs, :map, default: %{}
    field :deliverables, :map, default: %{}
    field :result_refs, :map, default: %{}
    field :runtime_state, :map, default: %{}
    field :metadata, :map, default: %{}

    belongs_to :assigned_agent, HydraX.Runtime.AgentProfile
    belongs_to :delegated_by_agent, HydraX.Runtime.AgentProfile
    belongs_to :parent_work_item, __MODULE__

    has_many :artifacts, HydraX.Runtime.Artifact
    has_many :approval_records, HydraX.Runtime.ApprovalRecord
    has_many :child_work_items, __MODULE__, foreign_key: :parent_work_item_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(work_item, attrs) do
    work_item
    |> cast(attrs, [
      :kind,
      :goal,
      :status,
      :execution_mode,
      :assigned_role,
      :assigned_agent_id,
      :delegated_by_agent_id,
      :parent_work_item_id,
      :priority,
      :autonomy_level,
      :review_required,
      :approval_stage,
      :deadline_at,
      :budget,
      :input_artifact_refs,
      :required_outputs,
      :deliverables,
      :result_refs,
      :runtime_state,
      :metadata
    ])
    |> validate_required([:kind, :goal, :status, :execution_mode, :assigned_role])
    |> validate_inclusion(:kind, @kinds)
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:execution_mode, @execution_modes)
    |> validate_inclusion(:assigned_role, Autonomy.roles())
    |> validate_inclusion(:autonomy_level, Autonomy.autonomy_levels())
    |> validate_inclusion(:approval_stage, @approval_stages)
    |> validate_number(:priority, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> assoc_constraint(:assigned_agent)
    |> assoc_constraint(:delegated_by_agent)
    |> assoc_constraint(:parent_work_item)
  end
end
