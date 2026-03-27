defmodule Mix.Tasks.HydraX.Simulation do
  @moduledoc """
  Manage Hydra-X simulations.

  ## Commands

      mix hydra_x.simulation                        # List simulations
      mix hydra_x.simulation create --name "Q3 Strategy"  # Create new
      mix hydra_x.simulation start ID                      # Start simulation
      mix hydra_x.simulation pause ID                      # Pause mid-run
      mix hydra_x.simulation resume ID                     # Resume
      mix hydra_x.simulation status ID                     # Show current state
      mix hydra_x.simulation report ID                     # Generate report
      mix hydra_x.simulation cost ID                       # Show cost breakdown
  """

  use Mix.Task

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    case args do
      [] -> list()
      ["create" | rest] -> create(rest)
      ["start", id] -> start_sim(id)
      ["pause", id] -> pause(id)
      ["resume", id] -> resume(id)
      ["status", id] -> status(id)
      ["report", id] -> report(id)
      ["cost", id] -> cost(id)
      ["export", id | rest] -> export(id, rest)
      ["replay", id | rest] -> replay(id, rest)
      _ -> Mix.shell().info("Unknown command. Run `mix help hydra_x.simulation` for usage.")
    end
  end

  defp list do
    import Ecto.Query

    sims =
      HydraX.Repo.all(
        from s in HydraX.Simulation.Schema.Simulation,
          order_by: [desc: s.inserted_at]
      )

    if sims == [] do
      Mix.shell().info("No simulations found.")
    else
      Mix.shell().info("ID  | Name                    | Status      | Ticks | Cost")
      Mix.shell().info(String.duplicate("-", 70))

      for sim <- sims do
        cost = "$#{(sim.total_cost_cents || 0) / 100}"

        Mix.shell().info(
          "#{String.pad_trailing(to_string(sim.id), 4)}| " <>
            "#{String.pad_trailing(sim.name || "", 24)}| " <>
            "#{String.pad_trailing(sim.status || "", 12)}| " <>
            "#{String.pad_trailing(to_string(sim.total_ticks || 0), 6)}| " <>
            cost
        )
      end
    end
  end

  defp create(args) do
    {opts, _, _} =
      OptionParser.parse(args, strict: [name: :string, ticks: :integer, budget: :integer])

    name = opts[:name] || "Untitled Simulation"

    config = %{
      "name" => name,
      "max_ticks" => opts[:ticks] || 40,
      "max_budget_cents" => opts[:budget] || 50
    }

    attrs = %{name: name, status: "configuring", config: config}

    case HydraX.Repo.insert(
           HydraX.Simulation.Schema.Simulation.changeset(
             %HydraX.Simulation.Schema.Simulation{},
             attrs
           )
         ) do
      {:ok, sim} ->
        Mix.shell().info("Created simulation #{sim.id}: #{sim.name}")

      {:error, changeset} ->
        Mix.shell().error("Failed: #{inspect(changeset.errors)}")
    end
  end

  defp start_sim(id) do
    sim = HydraX.Repo.get!(HydraX.Simulation.Schema.Simulation, id)
    Mix.shell().info("Starting simulation #{sim.name} (#{sim.id})...")
    Mix.shell().info("Use the LiveView UI at /simulations/#{id} for real-time monitoring.")
  end

  defp pause(id) do
    sim = HydraX.Repo.get!(HydraX.Simulation.Schema.Simulation, id)
    Mix.shell().info("Pausing simulation #{sim.name}")
  end

  defp resume(id) do
    sim = HydraX.Repo.get!(HydraX.Simulation.Schema.Simulation, id)
    Mix.shell().info("Resuming simulation #{sim.name}")
  end

  defp status(id) do
    sim = HydraX.Repo.get!(HydraX.Simulation.Schema.Simulation, id)

    Mix.shell().info("""
    Simulation: #{sim.name}
    Status:     #{sim.status}
    Ticks:      #{sim.total_ticks}
    LLM Calls:  #{sim.total_llm_calls}
    Tokens:     #{sim.total_tokens_used}
    Cost:       $#{(sim.total_cost_cents || 0) / 100}
    Started:    #{sim.started_at || "not started"}
    Completed:  #{sim.completed_at || "in progress"}
    """)
  end

  defp report(id) do
    sim = HydraX.Repo.get!(HydraX.Simulation.Schema.Simulation, id)
    Mix.shell().info("Generating report for #{sim.name}...")
    Mix.shell().info("View at /simulations/#{id}/report")
  end

  defp cost(id) do
    sim = HydraX.Repo.get!(HydraX.Simulation.Schema.Simulation, id)

    Mix.shell().info("""
    Cost Breakdown for: #{sim.name}
    Total LLM Calls:    #{sim.total_llm_calls || 0}
    Total Tokens:       #{sim.total_tokens_used || 0}
    Total Cost:         $#{(sim.total_cost_cents || 0) / 100}
    """)
  end

  defp export(id, args) do
    {opts, _, _} = OptionParser.parse(args, strict: [format: :string, output: :string])

    format = if opts[:format] == "markdown", do: :markdown, else: :json
    ext = if format == :markdown, do: "md", else: "json"
    output = opts[:output] || "simulation_#{id}.#{ext}"

    sim = HydraX.Repo.get!(HydraX.Simulation.Schema.Simulation, id)
    Mix.shell().info("Exporting #{sim.name} as #{format} to #{output}...")

    case HydraX.Simulation.export_file(String.to_integer(id), output, format) do
      :ok -> Mix.shell().info("Exported to #{output}")
      {:error, reason} -> Mix.shell().error("Export failed: #{inspect(reason)}")
    end
  end

  defp replay(id, args) do
    {opts, _, _} = OptionParser.parse(args, strict: [from: :integer, to: :integer])

    sim = HydraX.Repo.get!(HydraX.Simulation.Schema.Simulation, id)
    timeline = HydraX.Simulation.replay(String.to_integer(id), opts)

    Mix.shell().info("Replay: #{sim.name} (#{length(timeline)} ticks)")

    for tick <- timeline do
      event_count = length(tick[:events] || [])
      llm = tick[:llm_calls] || 0
      Mix.shell().info("  Tick #{tick.tick_number}: #{event_count} events, #{llm} LLM calls")
    end
  end
end
