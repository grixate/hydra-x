defmodule HydraX.Memory.Evidence do
  @moduledoc false

  @evidence_kinds ~w(claim source citation observation inference)
  @default_freshness_ttl_days 30

  def evidence_kinds, do: @evidence_kinds

  def evidence_metadata(kind, provenance, confidence, opts \\ [])
      when kind in @evidence_kinds do
    now = Keyword.get(opts, :freshness_at, DateTime.utc_now())

    %{
      "evidence_kind" => kind,
      "provenance" => provenance || %{},
      "confidence" => confidence,
      "freshness_at" => DateTime.to_iso8601(now),
      "freshness_ttl_days" => Keyword.get(opts, :freshness_ttl_days, @default_freshness_ttl_days),
      "approval_state" => Keyword.get(opts, :approval_state, "provisional")
    }
  end

  def stale?(metadata, now \\ DateTime.utc_now())

  def stale?(metadata, now) when is_map(metadata) do
    freshness_at = parse_datetime(metadata["freshness_at"])
    ttl_days = metadata["freshness_ttl_days"] || @default_freshness_ttl_days

    case freshness_at do
      nil ->
        expires_at = parse_datetime(metadata["expires_at"])

        case expires_at do
          nil -> false
          dt -> DateTime.compare(dt, now) == :lt
        end

      dt ->
        deadline = DateTime.add(dt, ttl_days * 24 * 60 * 60, :second)
        DateTime.compare(deadline, now) == :lt
    end
  end

  def stale?(_metadata, _now), do: false

  def approved?(metadata) when is_map(metadata) do
    metadata["approval_state"] == "approved"
  end

  def approved?(_metadata), do: false

  def provisional?(metadata) when is_map(metadata) do
    metadata["approval_state"] in ["provisional", nil]
  end

  def provisional?(_metadata), do: true

  def approve(metadata) when is_map(metadata) do
    metadata
    |> Map.put("approval_state", "approved")
    |> Map.put("approved_at", DateTime.utc_now() |> DateTime.to_iso8601())
  end

  def approve(metadata), do: metadata

  def mark_refreshed(metadata, now \\ DateTime.utc_now())

  def mark_refreshed(metadata, now) when is_map(metadata) do
    Map.put(metadata, "freshness_at", DateTime.to_iso8601(now))
  end

  def mark_refreshed(metadata, _now), do: metadata

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp parse_datetime(_value), do: nil
end
