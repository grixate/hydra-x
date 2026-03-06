defmodule HydraX.Memory.Markdown do
  @moduledoc false

  @spec render(list(HydraX.Memory.Entry.t())) :: String.t()
  def render(entries) do
    grouped = Enum.group_by(entries, & &1.type)

    content =
      grouped
      |> Enum.sort_by(fn {type, _entries} -> type end)
      |> Enum.map(fn {type, type_entries} ->
        body =
          type_entries
          |> Enum.sort_by(&{-&1.importance, &1.inserted_at}, {:desc, DateTime})
          |> Enum.map_join("\n", fn entry -> "- #{entry.content}" end)

        "## #{type}\n\n#{body}"
      end)
      |> Enum.join("\n\n")

    String.trim("""
    # Hydra-X Memory

    #{content}
    """)
  end
end
