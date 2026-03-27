defmodule HydraX.Simulation.Seed.SeedParser do
  @moduledoc """
  Parse seed material into a world model.

  Uses the existing Hydra-X ingest pipeline for document parsing, then
  runs LLM calls for entity extraction and persona generation.
  This is a setup-time operation (runs once before simulation starts).
  """

  alias HydraX.Simulation.Seed.{EntityExtractor, PersonaGenerator}

  @doc """
  Parse seed content into a world model with entities, relationships, and personas.

  Options:
  - :format - document format (default: ".md")
  - :agent_count - number of personas to generate (default: 20)
  - :llm_fn - custom LLM function for testing
  """
  @spec parse(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def parse(seed_content, opts \\ []) do
    format = Keyword.get(opts, :format, ".md")
    agent_count = Keyword.get(opts, :agent_count, 20)
    llm_fn = Keyword.get(opts, :llm_fn)

    with {:ok, chunks} <- parse_content(seed_content, format),
         {:ok, extracted} <- EntityExtractor.extract(chunks, llm_fn: llm_fn),
         {:ok, personas} <- PersonaGenerator.generate(extracted, agent_count, llm_fn: llm_fn) do
      {:ok,
       %{
         entities: extracted.entities,
         relationships: extracted.relationships,
         personas: personas,
         chunks: chunks
       }}
    end
  end

  @doc """
  Parse seed content into chunks using the ingest pipeline.
  """
  @spec parse_content(String.t(), String.t()) :: {:ok, [map()]} | {:error, term()}
  def parse_content(content, format) do
    case HydraX.Ingest.Parser.parse_content(format, content) do
      {:ok, chunks} -> {:ok, chunks}
      {:error, reason} -> {:error, {:parse_failed, reason}}
    end
  end
end
