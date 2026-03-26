defmodule Mix.Tasks.HydraX.Deploy do
  @moduledoc "Check production readiness and operating mode."
  @shortdoc "Production deployment readiness"
  use Mix.Task

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    case args do
      ["check"] -> check()
      ["mode"] -> mode()
      ["checklist"] -> check()
      _ -> usage()
    end
  end

  defp check do
    items = HydraX.Operator.Production.production_readiness()
    mode = HydraX.Operator.Production.operating_mode()

    Mix.shell().info("operating_mode=#{mode}")
    Mix.shell().info("")

    Enum.each(items, fn item ->
      status = if item.done, do: "OK", else: "MISSING"
      required = if item.required, do: "required", else: "optional"
      Mix.shell().info("[#{status}] #{item.step} (#{required})")
    end)

    blockers = HydraX.Operator.Production.production_blockers()

    if blockers != [] do
      Mix.shell().info("")
      Mix.shell().info("blockers=#{length(blockers)}")

      Enum.each(blockers, fn blocker ->
        Mix.shell().info("  - #{blocker}")
      end)
    else
      Mix.shell().info("")
      Mix.shell().info("All required items satisfied.")
    end
  end

  defp mode do
    mode = HydraX.Operator.Production.operating_mode()
    cluster = HydraX.Cluster.status()

    Mix.shell().info("operating_mode=#{mode}")
    Mix.shell().info("cluster_mode=#{cluster.mode}")
    Mix.shell().info("persistence=#{cluster.persistence}")
    Mix.shell().info("multi_node_ready=#{cluster.multi_node_ready}")
    Mix.shell().info("node_count=#{cluster.node_count}")
  end

  defp usage do
    Mix.shell().info("Usage: mix hydra_x.deploy <check|mode>")
    Mix.shell().info("")
    Mix.shell().info("  check     Print production readiness checklist")
    Mix.shell().info("  mode      Print current operating mode")
  end
end
