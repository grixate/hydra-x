defmodule HydraX.Runtime.ConversationBranch do
  @moduledoc """
  One row per (conversation, branch). The active branch for a conversation
  is identified by its `branch_uuid` matching `hx_conversations.active_branch_id`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias HydraX.Runtime.Conversation

  schema "hx_conversation_branches" do
    field :branch_uuid, Ecto.UUID
    field :label, :string, default: "main"
    field :forked_from_sequence, :integer

    belongs_to :conversation, Conversation
    belongs_to :parent_branch, __MODULE__

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(branch, attrs) do
    branch
    |> cast(attrs, [
      :conversation_id,
      :branch_uuid,
      :label,
      :forked_from_sequence,
      :parent_branch_id
    ])
    |> validate_required([:conversation_id, :branch_uuid, :label])
    |> assoc_constraint(:conversation)
    |> unique_constraint([:conversation_id, :branch_uuid])
    |> unique_constraint([:conversation_id, :label],
      name: :hx_conversation_branches_conversation_id_label_index,
      message: "branch label already exists in this conversation"
    )
  end
end
