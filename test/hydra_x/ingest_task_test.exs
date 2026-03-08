defmodule HydraX.IngestTaskTest do
  use HydraX.DataCase

  import ExUnit.CaptureIO

  alias HydraX.Runtime

  test "ingest task can import and list ingest-backed files" do
    Mix.Task.reenable("hydra_x.ingest")
    agent = create_agent()
    ingest_dir = Path.join(agent.workspace_root, "ingest")
    File.mkdir_p!(ingest_dir)
    File.write!(Path.join(ingest_dir, "ops.md"), "# Ops\n\nHydra-X ingest task works.")

    import_output =
      capture_io(fn ->
        Mix.Tasks.HydraX.Ingest.run(["import", "ops.md", "--agent", agent.slug])
      end)

    assert import_output =~ "file=ops.md"
    assert import_output =~ "created="

    Mix.Task.reenable("hydra_x.ingest")

    list_output =
      capture_io(fn ->
        Mix.Tasks.HydraX.Ingest.run(["--agent", agent.slug])
      end)

    assert list_output =~ "ops.md"
    assert list_output =~ "entries="

    Mix.Task.reenable("hydra_x.ingest")

    history_output =
      capture_io(fn ->
        Mix.Tasks.HydraX.Ingest.run(["history", "--agent", agent.slug])
      end)

    assert history_output =~ "ops.md"
    assert history_output =~ "status=imported"
  end

  test "ingest task records unchanged reimports and can force reingest" do
    Mix.Task.reenable("hydra_x.ingest")
    agent = create_agent()
    ingest_dir = Path.join(agent.workspace_root, "ingest")
    File.mkdir_p!(ingest_dir)
    File.write!(Path.join(ingest_dir, "ops.md"), "# Ops\n\nHydra-X ingest task works.")

    capture_io(fn ->
      Mix.Tasks.HydraX.Ingest.run(["import", "ops.md", "--agent", agent.slug])
    end)

    Mix.Task.reenable("hydra_x.ingest")

    unchanged_output =
      capture_io(fn ->
        Mix.Tasks.HydraX.Ingest.run(["import", "ops.md", "--agent", agent.slug])
      end)

    assert unchanged_output =~ "unchanged=true"

    Mix.Task.reenable("hydra_x.ingest")

    forced_output =
      capture_io(fn ->
        Mix.Tasks.HydraX.Ingest.run(["import", "ops.md", "--agent", agent.slug, "--force"])
      end)

    assert forced_output =~ "unchanged=false"

    Mix.Task.reenable("hydra_x.ingest")

    history_output =
      capture_io(fn ->
        Mix.Tasks.HydraX.Ingest.run(["history", "--agent", agent.slug, "--status", "skipped"])
      end)

    assert history_output =~ "ops.md"
    assert history_output =~ "status=skipped"
  end

  test "ingest task can import a pdf with an injected text extractor" do
    previous = Application.get_env(:hydra_x, :pdf_text_extractor)
    agent = create_agent()
    ingest_dir = Path.join(agent.workspace_root, "ingest")
    File.mkdir_p!(ingest_dir)
    pdf_path = Path.join(ingest_dir, "spec.pdf")
    File.write!(pdf_path, "fake-pdf")

    Application.put_env(:hydra_x, :pdf_text_extractor, fn ^pdf_path ->
      {:ok, "Hydra-X PDF paragraph one.\n\nHydra-X PDF paragraph two."}
    end)

    on_exit(fn ->
      if previous do
        Application.put_env(:hydra_x, :pdf_text_extractor, previous)
      else
        Application.delete_env(:hydra_x, :pdf_text_extractor)
      end
    end)

    Mix.Task.reenable("hydra_x.ingest")

    import_output =
      capture_io(fn ->
        Mix.Tasks.HydraX.Ingest.run(["import", "spec.pdf", "--agent", agent.slug])
      end)

    assert import_output =~ "file=spec.pdf"

    assert Enum.any?(
             HydraX.Memory.list_memories(agent_id: agent.id, status: "active", limit: 20),
             &String.contains?(&1.content, "Hydra-X PDF paragraph one.")
           )
  end

  defp create_agent do
    unique = System.unique_integer([:positive])

    {:ok, agent} =
      Runtime.save_agent(%{
        name: "Ingest Agent #{unique}",
        slug: "ingest-agent-#{unique}",
        workspace_root: Path.join(System.tmp_dir!(), "hydra-x-ingest-#{unique}"),
        description: "ingest test agent",
        is_default: false
      })

    agent
  end
end
