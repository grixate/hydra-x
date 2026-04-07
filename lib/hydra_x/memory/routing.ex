defmodule HydraX.Memory.Routing do
  @moduledoc false

  @scope_kinds ~w(agent conversation project channel workspace)
  @halls ~w(facts events discoveries preferences advice diary)

  def scope_kinds, do: @scope_kinds
  def halls, do: @halls

  def hall_for_type("Decision"), do: "facts"
  def hall_for_type("Preference"), do: "preferences"
  def hall_for_type("Goal"), do: "advice"
  def hall_for_type("Todo"), do: "advice"
  def hall_for_type("Event"), do: "events"
  def hall_for_type("Observation"), do: "discoveries"
  def hall_for_type(_type), do: "facts"

  def topic_key(value, opts \\ [])

  def topic_key(value, _opts) when value in [nil, ""], do: nil

  def topic_key(value, opts) when is_binary(value) do
    candidate =
      value
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/u, "-")
      |> String.replace(~r/^-+|-+$/u, "")
      |> String.slice(0, Keyword.get(opts, :max_length, 64))

    if candidate == "", do: nil, else: candidate
  end

  def topic_key(values, opts) when is_list(values) do
    values
    |> Enum.find_value(&topic_key(&1, opts))
  end

  def runtime_scope_key(attrs, existing \\ nil) do
    metadata = metadata(attrs, existing)

    cond do
      present?(attrs["scope_key"]) -> attrs["scope_key"]
      present?(metadata["scope_key"]) -> metadata["scope_key"]
      present?(metadata["project_id"]) -> "project:#{metadata["project_id"]}"
      present?(attrs["conversation_id"]) -> "conversation:#{attrs["conversation_id"]}"
      present?(metadata["source_channel"]) -> "channel:#{metadata["source_channel"]}"
      present?(attrs["agent_id"]) -> "agent:#{attrs["agent_id"]}"
      true -> nil
    end
  end

  def runtime_scope_kind(attrs, existing \\ nil) do
    metadata = metadata(attrs, existing)

    cond do
      attrs["scope_kind"] in @scope_kinds -> attrs["scope_kind"]
      metadata["scope_kind"] in @scope_kinds -> metadata["scope_kind"]
      present?(metadata["project_id"]) -> "project"
      present?(attrs["conversation_id"]) -> "conversation"
      present?(metadata["source_channel"]) -> "channel"
      present?(attrs["agent_id"]) -> "agent"
      true -> nil
    end
  end

  def runtime_topic_key(attrs, existing \\ nil) do
    metadata = metadata(attrs, existing)

    topic_key([
      attrs["topic_key"],
      metadata["topic_key"],
      metadata["topic"],
      metadata["source_section"],
      metadata["source_file"],
      attrs["content"],
      attrs["type"]
    ])
  end

  def runtime_hall(attrs, existing \\ nil) do
    metadata = metadata(attrs, existing)

    cond do
      attrs["hall"] in @halls -> attrs["hall"]
      metadata["hall"] in @halls -> metadata["hall"]
      true -> hall_for_type(attrs["type"] || existing_value(existing, :type))
    end
  end

  def parse_datetime(%DateTime{} = value), do: value

  def parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _ -> nil
    end
  end

  def parse_datetime(_value), do: nil

  def valid?(_record, as_of) when as_of in [nil, ""], do: true

  def valid?(record, as_of) do
    as_of = parse_datetime(as_of)
    valid_from = parse_datetime(field(record, :valid_from))
    valid_to = parse_datetime(field(record, :valid_to))

    not (compare_lt?(as_of, valid_from) or compare_gt?(as_of, valid_to))
  end

  def temporal_overlap?(left, right) do
    left_from = parse_datetime(field(left, :valid_from))
    left_to = parse_datetime(field(left, :valid_to))
    right_from = parse_datetime(field(right, :valid_from))
    right_to = parse_datetime(field(right, :valid_to))

    not (compare_lt?(left_to, right_from) or compare_lt?(right_to, left_from))
  end

  def product_metadata(attrs, record_type, project_id, existing_metadata \\ %{}) do
    metadata = Map.merge(existing_metadata || %{}, Map.get(attrs, "metadata", %{}))

    hall =
      cond do
        Map.get(attrs, "hall") in @halls -> Map.get(attrs, "hall")
        record_type in ["decision"] -> "facts"
        record_type in ["strategy", "requirement", "task"] -> "advice"
        record_type in ["insight", "learning"] -> "discoveries"
        true -> "facts"
      end

    topic =
      topic_key([
        metadata["topic_key"],
        metadata["topic"],
        attrs["title"],
        attrs["body"]
      ])

    metadata
    |> Map.put("scope_kind", "project")
    |> Map.put("scope_key", "project:#{project_id}")
    |> Map.put("hall", hall)
    |> Map.put("topic_key", topic)
    |> maybe_put("valid_from", attrs["valid_from"] || metadata["valid_from"])
    |> maybe_put("valid_to", attrs["valid_to"] || metadata["valid_to"])
  end

  defp field(record, key) when is_map(record) do
    Map.get(record, key) || Map.get(record, Atom.to_string(key))
  end

  defp metadata(attrs, existing) do
    Map.merge(existing_metadata(existing), Map.get(attrs, "metadata", %{}))
  end

  defp existing_metadata(nil), do: %{}
  defp existing_metadata(existing), do: field(existing, :metadata) || %{}

  defp existing_value(nil, _field), do: nil
  defp existing_value(existing, field), do: field(existing, field)

  defp present?(value), do: value not in [nil, ""]

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, %DateTime{} = value), do: Map.put(map, key, DateTime.to_iso8601(value))
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp compare_lt?(nil, _right), do: false
  defp compare_lt?(_left, nil), do: false
  defp compare_lt?(left, right), do: DateTime.compare(left, right) == :lt

  defp compare_gt?(nil, _right), do: false
  defp compare_gt?(_left, nil), do: false
  defp compare_gt?(left, right), do: DateTime.compare(left, right) == :gt
end
