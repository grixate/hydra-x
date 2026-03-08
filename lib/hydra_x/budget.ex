defmodule HydraX.Budget do
  @moduledoc """
  Budget policy persistence and token accounting.
  """

  import Ecto.Query

  alias HydraX.Budget.{Policy, Usage}
  alias HydraX.Repo

  @default_daily_limit 20_000
  @default_conversation_limit 4_000
  @default_soft_warning_at 0.8

  def ensure_policy!(agent_id) do
    get_policy(agent_id) ||
      case save_policy(%{
             agent_id: agent_id,
             daily_limit: @default_daily_limit,
             conversation_limit: @default_conversation_limit,
             soft_warning_at: @default_soft_warning_at,
             hard_limit_action: "reject",
             enabled: true
           }) do
        {:ok, policy} -> policy
        {:error, _changeset} -> get_policy(agent_id)
      end
  end

  def get_policy(agent_id) do
    Repo.get_by(Policy, agent_id: agent_id)
  end

  def change_policy(policy \\ %Policy{}, attrs \\ %{}) do
    Policy.changeset(policy, attrs)
  end

  def save_policy(attrs) when is_map(attrs), do: save_policy(%Policy{}, attrs)

  def save_policy(%Policy{} = policy, attrs) do
    policy
    |> Policy.changeset(attrs)
    |> Repo.insert_or_update()
  end

  def estimate_tokens(text) when is_binary(text) do
    text
    |> String.length()
    |> Kernel./(4)
    |> Float.ceil()
    |> trunc()
    |> max(1)
  end

  def estimate_tokens(nil), do: 1

  def estimate_prompt_tokens(messages) do
    messages
    |> Enum.map(fn message -> estimate_content_tokens(message.content) end)
    |> Enum.sum()
  end

  defp estimate_content_tokens(content) when is_binary(content), do: estimate_tokens(content)
  defp estimate_content_tokens(nil), do: 1

  defp estimate_content_tokens(blocks) when is_list(blocks) do
    Enum.reduce(blocks, 0, fn block, acc ->
      acc + estimate_content_tokens(block[:content] || block[:text] || block["content"] || block["text"] || "")
    end)
  end

  defp estimate_content_tokens(_), do: 1

  def preflight(agent_id, conversation_id, estimated_tokens) do
    policy = ensure_policy!(agent_id)

    if not policy.enabled do
      {:ok, %{policy: policy, warnings: [], usage: usage_snapshot(agent_id, conversation_id)}}
    else
      usage = usage_snapshot(agent_id, conversation_id)
      next_daily = usage.daily_tokens + estimated_tokens
      next_conversation = usage.conversation_tokens + estimated_tokens

      cond do
        next_daily > policy.daily_limit or next_conversation > policy.conversation_limit ->
          case policy.hard_limit_action do
            "warn" ->
              {:ok, %{policy: policy, usage: usage, warnings: [:hard_limit_reached]}}

            _ ->
              {:error,
               %{
                 policy: policy,
                 usage: usage,
                 estimated_tokens: estimated_tokens,
                 reason: :hard_limit_exceeded
               }}
          end

        next_daily >= trunc(policy.daily_limit * policy.soft_warning_at) or
            next_conversation >= trunc(policy.conversation_limit * policy.soft_warning_at) ->
          {:ok, %{policy: policy, usage: usage, warnings: [:soft_limit_reached]}}

        true ->
          {:ok, %{policy: policy, usage: usage, warnings: []}}
      end
    end
  end

  def record_usage(agent_id, conversation_id, attrs) do
    attrs = Map.new(attrs)

    %Usage{}
    |> Usage.changeset(%{
      agent_id: agent_id,
      conversation_id: conversation_id,
      scope: Map.get(attrs, :scope, "llm_completion"),
      tokens_in: Map.get(attrs, :tokens_in, 0),
      tokens_out: Map.get(attrs, :tokens_out, 0),
      metadata: Map.get(attrs, :metadata, %{})
    })
    |> Repo.insert()
  end

  def usage_snapshot(agent_id, conversation_id) do
    now = DateTime.utc_now()
    day_start = DateTime.new!(Date.utc_today(), ~T[00:00:00], "Etc/UTC")

    daily_tokens =
      Repo.one(
        from usage in Usage,
          where: usage.agent_id == ^agent_id and usage.inserted_at >= ^day_start,
          select: coalesce(sum(usage.tokens_in + usage.tokens_out), 0)
      )

    conversation_tokens =
      if is_nil(conversation_id) do
        0
      else
        Repo.one(
          from usage in Usage,
            where: usage.agent_id == ^agent_id and usage.conversation_id == ^conversation_id,
            select: coalesce(sum(usage.tokens_in + usage.tokens_out), 0)
        )
      end

    %{
      day: Date.to_iso8601(DateTime.to_date(now)),
      daily_tokens: daily_tokens,
      conversation_tokens: conversation_tokens
    }
  end

  def recent_usage(agent_id, limit \\ 20) do
    Usage
    |> where([usage], usage.agent_id == ^agent_id)
    |> order_by([usage], desc: usage.inserted_at)
    |> limit(^limit)
    |> preload([:conversation])
    |> Repo.all()
  end
end
