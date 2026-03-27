defmodule HydraX.Simulation.Agent.Population do
  @moduledoc """
  Batch agent spawner and profile generator.

  Spawns a population of SimAgent processes from a list of persona definitions,
  under a given DynamicSupervisor.
  """

  alias HydraX.Simulation.Agent.{SimAgent, Persona}

  @doc """
  Spawn a population of SimAgents under the given supervisor.

  Each persona in the list will be started as a SimAgent process.
  Returns {:ok, agent_ids} or {:error, reason} on first failure.
  """
  @spec spawn_population(pid() | atom(), String.t(), [Persona.t()], keyword()) ::
          {:ok, [String.t()]} | {:error, term()}
  def spawn_population(supervisor, sim_id, personas, opts \\ []) do
    base_seed = Keyword.get(opts, :rng_seed)

    results =
      personas
      |> Enum.with_index()
      |> Enum.map(fn {persona, index} ->
        agent_id = agent_id(persona, index)

        seed =
          if base_seed do
            base_seed + index
          else
            :erlang.phash2({sim_id, agent_id})
          end

        child_opts = [
          sim_id: sim_id,
          agent_id: agent_id,
          persona: persona,
          seed: seed,
          novelty_threshold: Keyword.get(opts, :novelty_threshold, 2),
          stakes_threshold: Keyword.get(opts, :stakes_threshold, 0.7),
          llm_request_callback: Keyword.get(opts, :llm_request_callback)
        ]

        case DynamicSupervisor.start_child(supervisor, {SimAgent, child_opts}) do
          {:ok, _pid} -> {:ok, agent_id}
          {:error, reason} -> {:error, {agent_id, reason}}
        end
      end)

    errors = Enum.filter(results, &match?({:error, _}, &1))

    if errors == [] do
      {:ok, Enum.map(results, fn {:ok, id} -> id end)}
    else
      {:error, {:spawn_failures, Enum.map(errors, fn {:error, e} -> e end)}}
    end
  end

  @doc """
  Generate a population of personas from archetype distribution.

  Given a total count and a distribution map like `%{cautious_cfo: 3, visionary_ceo: 2}`,
  generates that many personas with unique names.
  """
  @spec from_archetypes(map(), keyword()) :: [Persona.t()]
  def from_archetypes(distribution, _opts \\ []) do
    distribution
    |> Enum.flat_map(fn {archetype, count} ->
      base = Persona.archetype(archetype)

      Enum.map(1..count, fn i ->
        %{base | name: "#{base.name} #{i}"}
      end)
    end)
  end

  defp agent_id(%Persona{name: name}, index) do
    slug =
      name
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "_")
      |> String.trim("_")

    "#{slug}_#{index}"
  end
end
