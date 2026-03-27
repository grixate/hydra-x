defmodule HydraX.Tool.Registry do
  @moduledoc false

  alias HydraX.Tools.{
    BrowserAutomation,
    HttpFetch,
    MCPCatalog,
    MCPInspect,
    MCPInvoke,
    MCPProbe,
    MemoryRecall,
    MemorySave,
    Reply,
    ShellCommand,
    SkillInspect,
    WebSearch,
    WorkspaceList,
    WorkspacePatch,
    WorkspaceRead,
    WorkspaceWrite
  }

  @all_tools [
    {WorkspaceList, :workspace_list_enabled},
    {HttpFetch, :http_fetch_enabled},
    {BrowserAutomation, :browser_automation_enabled},
    {ShellCommand, :shell_command_enabled},
    {WorkspaceRead, :workspace_read_enabled},
    {WorkspaceWrite, :workspace_write_enabled},
    {WorkspacePatch, :workspace_write_enabled},
    {WebSearch, :web_search_enabled},
    {MCPCatalog, nil},
    {MCPInspect, nil},
    {MCPInvoke, nil},
    {MCPProbe, nil},
    {SkillInspect, nil},
    {MemoryRecall, nil},
    {MemorySave, nil},
    {Reply, nil}
  ]

  @doc """
  Returns tool schemas filtered by the effective tool policy.
  Tools without a policy gate (memory, reply) are always included.
  """
  def available_schemas(tool_policy \\ %{}, opts \\ %{}) do
    all_tools(opts)
    |> Enum.filter(fn {_mod, gate} -> gate == nil or Map.get(tool_policy, gate, true) end)
    |> Enum.map(fn {mod, _gate} -> mod.tool_schema() end)
  end

  @doc """
  Returns tool modules filtered by the effective tool policy.
  """
  def available_tools(tool_policy \\ %{}, opts \\ %{}) do
    all_tools(opts)
    |> Enum.filter(fn {_mod, gate} -> gate == nil or Map.get(tool_policy, gate, true) end)
    |> Enum.map(fn {mod, _gate} -> mod end)
  end

  @doc """
  Looks up a tool module by name string.
  """
  def find_tool(name, opts \\ %{}) do
    Enum.find_value(all_tools(opts), fn {mod, _gate} ->
      if mod.name() == name, do: mod
    end)
  end

  defp all_tools(opts) do
    @all_tools ++ normalize_extra_tools(opts)
  end

  defp normalize_extra_tools(opts) do
    opts
    |> extra_tools()
    |> Enum.uniq()
    |> Enum.map(&{&1, nil})
  end

  defp extra_tools(opts) when is_map(opts), do: Map.get(opts, :extra_tools, [])
  defp extra_tools(opts) when is_list(opts), do: Keyword.get(opts, :extra_tools, [])
  defp extra_tools(_opts), do: []
end
