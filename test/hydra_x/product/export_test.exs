defmodule HydraX.Product.ExportTest do
  use HydraX.DataCase

  alias HydraX.Product
  alias HydraX.Product.AgentBridge

  test "export_project_snapshot writes markdown json bundle and transcripts" do
    {:ok, project} = Product.create_project(%{"name" => "Export Graph"})

    {:ok, source} =
      Product.create_source(project, %{
        "title" => "Interview",
        "content" => "Operators need launch review workflows and weekly summaries."
      })

    chunk = hd(source.source_chunks)

    {:ok, insight} =
      Product.create_insight(project, %{
        "title" => "Launch Reviews",
        "body" => "Operators need launch review workflows.",
        "evidence_chunk_ids" => [chunk.id],
        "status" => "accepted"
      })

    {:ok, _requirement} =
      Product.create_requirement(project, %{
        "title" => "Support Launch Reviews",
        "body" => "The product must support launch review workflows.",
        "insight_ids" => [insight.id],
        "status" => "accepted"
      })

    {:ok, conversation} =
      AgentBridge.ensure_project_conversation(project, :researcher, %{
        "external_ref" => "export-graph"
      })

    {:ok, _result} = AgentBridge.submit_message(conversation, "Summarize the grounded evidence.")

    output_root =
      Path.join(System.tmp_dir!(), "hydra-x-product-export-#{System.unique_integer([:positive])}")

    export = Product.export_project_snapshot(project, output_root)

    assert File.exists?(export.markdown_path)
    assert File.exists?(export.json_path)
    assert File.dir?(export.bundle_dir)
    assert File.exists?(Path.join(export.bundle_dir, "manifest.json"))
    assert File.exists?(Path.join(export.bundle_dir, "project.json"))
    assert File.exists?(Path.join(export.bundle_dir, "sources.json"))
    assert File.exists?(Path.join(export.bundle_dir, "insights.json"))
    assert File.exists?(Path.join(export.bundle_dir, "requirements.json"))
    assert File.exists?(Path.join(export.bundle_dir, "conversations.json"))

    transcripts =
      Path.join(export.bundle_dir, "transcripts")
      |> File.ls!()

    assert transcripts != []
    assert File.read!(export.markdown_path) =~ "Export Graph Product Export"
    assert File.read!(export.json_path) =~ "\"slug\": \"export-graph\""
  end
end
