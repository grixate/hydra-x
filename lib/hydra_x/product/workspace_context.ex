defmodule HydraX.Product.WorkspaceContext do
  @moduledoc """
  Loads project-level instruction files (HYDRA.md, AGENTS.md, CLAUDE.md) from
  a per-project workspace and formats them into a single system-prompt
  section that `HydraX.Agent.PromptBuilder` can splice in.

  This is the project equivalent of agent-level `SOUL.md`/`IDENTITY.md` files
  loaded by `HydraX.Workspace.load_context/1` — the agent identity lives at
  the agent scope, while project conventions live at the project scope.

  Files are loaded fresh on every call (no caching). If the workspace doesn't
  exist or the project_id is nil, returns an empty string so callers can
  splice unconditionally.
  """

  alias HydraX.Product.Workspace
  alias HydraX.Product.Workspaces

  @instruction_files ["HYDRA.md", "AGENTS.md", "CLAUDE.md"]
  # Per-file cap so that a runaway HYDRA.md doesn't blow the system prompt
  # token budget on every LLM call. Files larger than this get truncated
  # with a marker; the agent can read the rest via `code_read` if needed.
  @max_file_bytes 32_000
  @truncation_marker "\n\n…[truncated — read the full file via code_read]"

  @doc "Returns the list of filenames searched for, in priority order."
  def instruction_files, do: @instruction_files

  @doc """
  Load instructions for a given project. Returns a list of
  `%{file: name, content: binary}` entries — one per file present.
  Missing files are skipped silently.
  """
  def load(project_id) when is_integer(project_id) do
    case Workspaces.get_for_project(project_id) do
      nil ->
        []

      %Workspace{fs_path: fs_path} ->
        # Read directly via File.read so that probing for instruction files
        # does NOT emit a workspace_event audit row on every prompt build.
        # The backend's audit path is for actual agent ops, not for our
        # internal prompt-context probes.
        @instruction_files
        |> Enum.flat_map(fn name ->
          path = Path.join(fs_path, name)

          case File.read(path) do
            {:ok, content} when is_binary(content) and content != "" ->
              [%{file: name, content: cap_content(content)}]

            _ ->
              []
          end
        end)
    end
  end

  def load(_), do: []

  defp cap_content(content) when byte_size(content) <= @max_file_bytes, do: content

  defp cap_content(content) do
    binary_part(content, 0, @max_file_bytes) <> @truncation_marker
  end

  @doc """
  Format loaded instructions as a single string suitable for splicing into a
  system prompt. Returns an empty string when no instructions are present so
  that callers can pass it unconditionally without producing a blank section.
  """
  def format(project_id) do
    case load(project_id) do
      [] ->
        ""

      entries ->
        entries
        |> Enum.map_join("\n\n---\n\n", fn entry ->
          "## #{entry.file}\n\n#{entry.content}"
        end)
    end
  end

  @doc """
  Convenience: extract `product_project_id` from a `%Conversation{}` (or its
  metadata map) and call `format/1`. Returns `""` when no project is bound.
  """
  def format_for_conversation(%{metadata: metadata}) when is_map(metadata) do
    case parse_int(metadata["product_project_id"]) do
      {:ok, id} -> format(id)
      :error -> ""
    end
  end

  def format_for_conversation(_), do: ""

  defp parse_int(n) when is_integer(n) and n > 0, do: {:ok, n}

  defp parse_int(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, ""} when n > 0 -> {:ok, n}
      _ -> :error
    end
  end

  defp parse_int(_), do: :error
end
