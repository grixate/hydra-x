defmodule HydraX.Runtime.ApprovalRecord do
  use Ecto.Schema
  import Ecto.Changeset

  @subject_types ~w(work_item artifact)
  @decisions ~w(requested approved rejected superseded)

  schema "hx_approval_records" do
    field :subject_type, :string
    field :subject_id, :integer
    field :requested_action, :string
    field :decision, :string
    field :rationale, :string
    field :promoted_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    belongs_to :work_item, HydraX.Runtime.WorkItem
    belongs_to :reviewer_agent, HydraX.Runtime.AgentProfile

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [
      :subject_type,
      :subject_id,
      :requested_action,
      :decision,
      :rationale,
      :promoted_at,
      :metadata,
      :work_item_id,
      :reviewer_agent_id
    ])
    |> validate_required([:subject_type, :subject_id, :requested_action, :decision])
    |> validate_inclusion(:subject_type, @subject_types)
    |> validate_inclusion(:decision, @decisions)
    |> validate_number(:subject_id, greater_than: 0)
    |> assoc_constraint(:work_item)
    |> assoc_constraint(:reviewer_agent)
  end
end
