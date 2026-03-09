defmodule HydraX.Tool.Registry do
  @moduledoc false

  alias HydraX.Tools.{
    HttpFetch,
    MemoryRecall,
    MemorySave,
    Reply,
    ShellCommand,
    WebSearch,
    WorkspaceList,
    WorkspacePatch,
    WorkspaceRead,
    WorkspaceWrite
  }

  @all_tools [
    {WorkspaceList, :workspace_list_enabled},
    {HttpFetch, :http_fetch_enabled},
    {ShellCommand, :shell_command_enabled},
    {WorkspaceRead, :workspace_read_enabled},
    {WorkspaceWrite, :workspace_write_enabled},
    {WorkspacePatch, :workspace_write_enabled},
    {WebSearch, :web_search_enabled},
    {MemoryRecall, nil},
    {MemorySave, nil},
    {Reply, nil}
  ]

  @doc """
  Returns tool schemas filtered by the effective tool policy.
  Tools without a policy gate (memory, reply) are always included.
  """
  def available_schemas(tool_policy \\ %{}) do
    @all_tools
    |> Enum.filter(fn {_mod, gate} -> gate == nil or Map.get(tool_policy, gate, true) end)
    |> Enum.map(fn {mod, _gate} -> mod.tool_schema() end)
  end

  @doc """
  Returns tool modules filtered by the effective tool policy.
  """
  def available_tools(tool_policy \\ %{}) do
    @all_tools
    |> Enum.filter(fn {_mod, gate} -> gate == nil or Map.get(tool_policy, gate, true) end)
    |> Enum.map(fn {mod, _gate} -> mod end)
  end

  @doc """
  Looks up a tool module by name string.
  """
  def find_tool(name) do
    Enum.find_value(@all_tools, fn {mod, _gate} ->
      if mod.name() == name, do: mod
    end)
  end
end
