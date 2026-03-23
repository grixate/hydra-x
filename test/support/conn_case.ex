defmodule HydraXWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use HydraXWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint HydraXWeb.Endpoint

      use HydraXWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import Phoenix.LiveViewTest
      import HydraXWeb.ConnCase
    end
  end

  setup tags do
    pid = HydraX.DataCase.setup_sandbox(tags)

    metadata =
      HydraX.Repo
      |> Phoenix.Ecto.SQL.Sandbox.metadata_for(pid)
      |> Phoenix.Ecto.SQL.Sandbox.encode_metadata()

    conn =
      Phoenix.ConnTest.build_conn()
      |> Plug.Conn.put_req_header("user-agent", metadata)

    if Map.get(tags, :seed_default_agent, true) do
      seed_default_agent()
    end

    {:ok, conn: conn}
  end

  defp seed_default_agent do
    workspace_root = HydraX.Config.default_workspace("hydra-primary")
    HydraX.Workspace.Scaffold.copy_template!(workspace_root)

    attrs = %{
      name: "Hydra Prime",
      slug: "hydra-primary",
      status: "active",
      description: "Default Hydra-X operator agent",
      is_default: true,
      workspace_root: workspace_root,
      runtime_state: %{}
    }

    changeset =
      HydraX.Runtime.AgentProfile.changeset(%HydraX.Runtime.AgentProfile{}, attrs)

    retry_on_busy(fn ->
      HydraX.Repo.insert(
        changeset,
        on_conflict: [
          set: [
            name: attrs.name,
            status: attrs.status,
            description: attrs.description,
            is_default: attrs.is_default,
            workspace_root: attrs.workspace_root,
            runtime_state: attrs.runtime_state,
            updated_at: DateTime.utc_now()
          ]
        ],
        conflict_target: :slug
      )
    end)
  end

  defp retry_on_busy(fun, attempts \\ 10)

  defp retry_on_busy(fun, attempts) do
    fun.()
  rescue
    error in Exqlite.Error ->
      if attempts > 1 and String.contains?(Exception.message(error), "Database busy") do
        Process.sleep((11 - attempts) * 25)
        retry_on_busy(fun, attempts - 1)
      else
        reraise error, __STACKTRACE__
      end
  end
end
