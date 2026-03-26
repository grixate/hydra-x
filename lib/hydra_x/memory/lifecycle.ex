defmodule HydraX.Memory.Lifecycle do
  @moduledoc false

  alias HydraX.Memory
  alias HydraX.Memory.Evidence

  @promotable_statuses ["candidate"]
  @expirable_statuses ["active", "durable"]
  @min_promotion_confidence 0.5

  def promotable?(%{status: status, metadata: metadata}) when is_map(metadata) do
    status in @promotable_statuses and
      Evidence.approved?(metadata) and
      (metadata["confidence"] || 0) >= @min_promotion_confidence
  end

  def promotable?(%{status: _status, metadata: _metadata}), do: false

  def promotable?(_entry), do: false

  def promote(%{metadata: metadata} = _entry) do
    %{
      "status" => "durable",
      "metadata" =>
        Map.merge(metadata || %{}, %{
          "promoted_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
          "promotion_state" => "durable"
        })
    }
  end

  def expire(%{metadata: metadata} = _entry) do
    %{
      "status" => "archived",
      "metadata" =>
        Map.merge(metadata || %{}, %{
          "expired_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
          "expiry_reason" => "ttl"
        })
    }
  end

  def expired?(entry, now \\ DateTime.utc_now())

  def expired?(%{metadata: metadata}, now) when is_map(metadata) do
    Evidence.stale?(metadata, now)
  end

  def expired?(_entry, _now), do: false

  def lifecycle_state(%{status: status, metadata: metadata}) do
    cond do
      status == "durable" -> :durable
      status == "candidate" -> :candidate
      status == "scratch" -> :scratch
      status == "active" and metadata["promotion_state"] == "durable" -> :durable
      status == "active" -> :active
      status in ["conflicted", "superseded", "merged", "archived"] -> String.to_atom(status)
      true -> :unknown
    end
  end

  def lifecycle_state(_entry), do: :unknown

  def expire_stale_memories!(agent_id, now \\ DateTime.utc_now()) do
    Memory.list_memories(agent_id: agent_id, limit: 200)
    |> Enum.filter(fn entry ->
      entry.status in @expirable_statuses and expired?(entry, now)
    end)
    |> Enum.reduce(0, fn entry, count ->
      case Memory.update_memory(entry, expire(entry)) do
        {:ok, _} -> count + 1
        _ -> count
      end
    end)
  end

  def promote_candidates!(agent_id) do
    Memory.list_memories(agent_id: agent_id, status: "candidate", limit: 200)
    |> Enum.filter(&promotable?/1)
    |> Enum.reduce(0, fn entry, count ->
      case Memory.update_memory(entry, promote(entry)) do
        {:ok, _} -> count + 1
        _ -> count
      end
    end)
  end
end
