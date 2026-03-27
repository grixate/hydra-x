defmodule HydraX.Simulation do
  @moduledoc """
  Public API facade for the Hydra-X simulation engine.

  The simulation engine spawns populations of simulated agents with distinct
  personalities modeled as `gen_statem` FSMs, runs them through discrete ticks
  in a shared world model, and synthesizes findings via a report agent.

  ## Three-tier decision architecture

  - **Routine** (~70%): Pure rules engine, no LLM cost
  - **Emotional** (~10%): Personality-driven fast path, no LLM cost
  - **Complex** (~15%): Cheap LLM (DeepSeek/Ollama)
  - **Negotiation** (~5%): Frontier LLM (Claude/GPT)

  Cost target: ~$0.15 per 100-agent, 40-round simulation run.
  """

  alias HydraX.Simulation.Config
  alias HydraX.Simulation.Agent.{Persona, Population}
  alias HydraX.Simulation.Engine.{Runner, Replay, Export}
  alias HydraX.Simulation.Seed.SeedParser
  alias HydraX.Simulation.Report.ReportAgent

  # --- Lifecycle ---

  @doc """
  Start a new simulation with the given config and personas.
  Returns {:ok, sim_id} or {:error, reason}.
  """
  defdelegate start(config, personas, opts \\ []), to: Runner

  @doc "Run (start ticking) a simulation."
  defdelegate run(sim_id), to: Runner

  @doc "Pause a running simulation."
  defdelegate pause(sim_id), to: Runner

  @doc "Resume a paused simulation."
  defdelegate resume(sim_id), to: Runner

  @doc "Get the current status of a simulation."
  defdelegate status(sim_id), to: Runner

  # --- Persona & Population ---

  @doc "List available persona archetypes."
  @spec archetypes() :: [atom()]
  def archetypes, do: Persona.archetypes()

  @doc "Get a persona archetype by name."
  @spec archetype(atom()) :: Persona.t()
  def archetype(name), do: Persona.archetype(name)

  @doc "Generate a population of personas from an archetype distribution."
  @spec generate_population(map()) :: [Persona.t()]
  def generate_population(distribution), do: Population.from_archetypes(distribution)

  # --- Config ---

  @doc "Create and validate a simulation config."
  @spec create_config(map()) :: {:ok, Config.t()} | {:error, term()}
  def create_config(attrs) do
    config = Config.new(attrs)

    case Config.validate(config) do
      {:ok, config} -> {:ok, config}
      {:error, reasons} -> {:error, {:invalid_config, reasons}}
    end
  end

  # --- Seed Ingestion ---

  @doc "Parse seed material into a world model with entities and personas."
  defdelegate parse_seed(content, opts \\ []), to: SeedParser, as: :parse

  # --- Report ---

  @doc "Generate a post-simulation report."
  defdelegate generate_report(sim_id, opts \\ []), to: ReportAgent, as: :generate

  # --- Replay & Export ---

  @doc "Build a replay timeline for a simulation."
  defdelegate replay(simulation_id, opts \\ []), to: Replay, as: :build_timeline

  @doc "Export simulation data as JSON."
  defdelegate export_json(simulation_id), to: Export, as: :to_json

  @doc "Export simulation data as Markdown."
  defdelegate export_markdown(simulation_id), to: Export, as: :to_markdown

  @doc "Write simulation export to a file."
  defdelegate export_file(simulation_id, path, format \\ :json), to: Export, as: :write_file
end
