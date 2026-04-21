defmodule HydraX.Runtime.SessionBranches do
  @moduledoc """
  Branching for `HydraX.Runtime.Conversation` turns. Each conversation has
  one or more branches; one is `active`. Sequences are scoped per-branch so
  appending a turn never collides across branches.

  ## Model

  - `hx_conversation_branches` — one row per branch, with a `branch_uuid`
    that is unique within the conversation. The `main` branch is created
    automatically the first time a branch operation runs against a
    conversation.
  - `hx_conversations.active_branch_id` — the `branch_uuid` whose turns are
    currently shown by `Runtime.Conversations.list_turns/1`.
  - `hx_turns.branch_id` — the `branch_uuid` this turn belongs to.

  Forking creates a new branch with `parent_branch_id` and
  `forked_from_sequence` set, and switches the conversation's
  `active_branch_id` to the new branch. Future appended turns land in the
  new branch starting from sequence 1.
  """

  import Ecto.Query

  alias HydraX.Repo
  alias HydraX.Runtime.Conversation
  alias HydraX.Runtime.ConversationBranch
  alias HydraX.Runtime.Turn

  @doc "Lists all branches for a conversation, oldest first."
  def list(conversation_id) when is_integer(conversation_id) do
    ConversationBranch
    |> where([b], b.conversation_id == ^conversation_id)
    |> order_by([b], asc: b.inserted_at)
    |> Repo.all()
  end

  @doc "Returns the conversation's active branch row, or nil."
  def active_branch(%Conversation{id: id, active_branch_id: nil} = _conv) do
    # Conversation predates branches and was never updated by code paths that
    # backfill — should never happen post-migration, but be defensive.
    ensure_main_branch(id)
  end

  def active_branch(%Conversation{active_branch_id: uuid} = conv) do
    Repo.get_by(ConversationBranch, conversation_id: conv.id, branch_uuid: uuid)
  end

  def active_branch(conversation_id) when is_integer(conversation_id) do
    case Repo.get(Conversation, conversation_id) do
      nil -> nil
      conv -> active_branch(conv)
    end
  end

  @doc """
  Ensures a `main` branch exists for the given conversation and that the
  conversation's `active_branch_id` points at it. Idempotent.
  Returns the main branch row.
  """
  def ensure_main_branch(conversation_id) when is_integer(conversation_id) do
    case fetch_main_branch(conversation_id) do
      %ConversationBranch{} = branch ->
        branch

      nil ->
        attrs = %{
          conversation_id: conversation_id,
          branch_uuid: Ecto.UUID.generate(),
          label: "main"
        }

        case %ConversationBranch{} |> ConversationBranch.changeset(attrs) |> Repo.insert() do
          {:ok, branch} ->
            update_active_branch_if_unset!(conversation_id, branch.branch_uuid)
            branch

          {:error, %Ecto.Changeset{}} ->
            # Lost the race with another process that inserted main first.
            # Re-fetch and return their row.
            fetch_main_branch(conversation_id) ||
              raise "ensure_main_branch race lost but no main row found"
        end
    end
  end

  defp fetch_main_branch(conversation_id) do
    Repo.one(
      from b in ConversationBranch,
        where: b.conversation_id == ^conversation_id and b.label == "main"
    )
  end

  @doc """
  Fork a new branch starting from the given turn. By default the new branch
  becomes active; pass `switch?: false` to create the branch without
  changing the conversation's active branch (useful for "save this approach
  for later" workflows).

  `from_turn` is the last turn in the parent branch that the fork sees;
  the new branch starts as if the conversation history ended at
  `from_turn.sequence`.

  Returns `{:ok, new_branch}` or `{:error, reason}`.
  """
  def fork(%Turn{} = from_turn, label, opts \\ []) when is_binary(label) do
    switch? = Keyword.get(opts, :switch?, true)

    parent_branch =
      Repo.get_by(ConversationBranch,
        conversation_id: from_turn.conversation_id,
        branch_uuid: from_turn.branch_id
      )

    case parent_branch do
      nil ->
        {:error, :parent_branch_not_found}

      %ConversationBranch{} = parent ->
        attrs = %{
          conversation_id: from_turn.conversation_id,
          branch_uuid: Ecto.UUID.generate(),
          label: label,
          parent_branch_id: parent.id,
          forked_from_sequence: from_turn.sequence
        }

        with {:ok, branch} <-
               %ConversationBranch{} |> ConversationBranch.changeset(attrs) |> Repo.insert(),
             {:ok, _maybe_conv} <- maybe_activate(branch, switch?) do
          {:ok, branch}
        end
    end
  end

  defp maybe_activate(%ConversationBranch{} = branch, true),
    do: set_active_branch(branch.conversation_id, branch.branch_uuid)

  defp maybe_activate(%ConversationBranch{} = branch, false), do: {:ok, branch}

  @doc """
  Switch the conversation's active branch to the given branch_uuid.
  Returns `{:ok, conversation}` or `{:error, reason}`.
  """
  def switch(conversation_id, branch_uuid) when is_integer(conversation_id) do
    case Repo.get_by(ConversationBranch,
           conversation_id: conversation_id,
           branch_uuid: branch_uuid
         ) do
      nil -> {:error, :branch_not_found}
      %ConversationBranch{} -> set_active_branch(conversation_id, branch_uuid)
    end
  end

  @doc """
  List branches that forked from the given turn. A branch forks from `turn`
  when its `parent_branch_id` is the branch that contains `turn` and its
  `forked_from_sequence` equals `turn.sequence`. Returns an empty list when
  the turn's branch row can't be resolved (e.g. pre-branching conversation).
  """
  def branches_at(%Turn{} = turn) do
    case Repo.get_by(ConversationBranch,
           conversation_id: turn.conversation_id,
           branch_uuid: turn.branch_id
         ) do
      nil ->
        []

      %ConversationBranch{id: parent_id} ->
        ConversationBranch
        |> where(
          [b],
          b.parent_branch_id == ^parent_id and b.forked_from_sequence == ^turn.sequence
        )
        |> order_by([b], asc: b.inserted_at)
        |> Repo.all()
    end
  end

  @doc """
  Returns the branch tree for visualisation: list of `%{branch, turn_count, parent_branch_id}`
  sorted by inserted_at.
  """
  def tree(conversation_id) when is_integer(conversation_id) do
    branches = list(conversation_id)

    counts =
      from(t in Turn,
        where: t.conversation_id == ^conversation_id,
        group_by: t.branch_id,
        select: {t.branch_id, count(t.id)}
      )
      |> Repo.all()
      |> Map.new()

    Enum.map(branches, fn branch ->
      %{
        id: branch.id,
        branch_uuid: branch.branch_uuid,
        label: branch.label,
        parent_branch_id: branch.parent_branch_id,
        forked_from_sequence: branch.forked_from_sequence,
        turn_count: Map.get(counts, branch.branch_uuid, 0),
        inserted_at: branch.inserted_at
      }
    end)
  end

  # ---------------------------------------------------------------------------
  # Internals
  # ---------------------------------------------------------------------------

  defp set_active_branch(conversation_id, branch_uuid) do
    Conversation
    |> Repo.get!(conversation_id)
    |> Conversation.changeset(%{active_branch_id: branch_uuid})
    |> Repo.update()
  end

  defp update_active_branch_if_unset!(conversation_id, branch_uuid) do
    from(c in Conversation,
      where: c.id == ^conversation_id and is_nil(c.active_branch_id),
      update: [set: [active_branch_id: ^branch_uuid]]
    )
    |> Repo.update_all([])
  end
end
