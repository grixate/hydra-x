defmodule HydraX.Memory.ResearchDelta do
  @moduledoc false

  def build(before_counts, after_counts) when is_map(before_counts) and is_map(after_counts) do
    %{
      "promoted" => delta(before_counts, after_counts, "durable"),
      "expired" => -delta(before_counts, after_counts, "active") +
        -delta(before_counts, after_counts, "durable"),
      "new_candidates" => delta(before_counts, after_counts, "candidate"),
      "archived" => delta(before_counts, after_counts, "archived"),
      "superseded" => delta(before_counts, after_counts, "superseded")
    }
    |> Map.reject(fn {_k, v} -> v == 0 end)
  end

  def build(_before, _after), do: %{}

  def format_summary(delta) when is_map(delta) do
    parts =
      [
        format_part(delta, "promoted", "promoted"),
        format_part(delta, "expired", "expired"),
        format_part(delta, "new_candidates", "new candidates"),
        format_part(delta, "archived", "archived"),
        format_part(delta, "superseded", "superseded")
      ]
      |> Enum.reject(&is_nil/1)

    case parts do
      [] -> "No changes"
      parts -> Enum.join(parts, ", ")
    end
  end

  def format_summary(_delta), do: "No changes"

  defp delta(before, after_counts, key) do
    (after_counts[key] || 0) - (before[key] || 0)
  end

  defp format_part(delta, key, label) do
    case delta[key] do
      nil -> nil
      0 -> nil
      n when n > 0 -> "#{n} #{label}"
      n -> "#{n} #{label}"
    end
  end
end
