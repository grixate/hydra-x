defmodule HydraX.Simulation.Seed.SeedParserTest do
  use ExUnit.Case, async: true

  alias HydraX.Simulation.Seed.SeedParser

  @sample_seed """
  ## Company Overview

  TechCorp is a mid-size technology company with 500 employees.
  They compete with MegaTech in the cloud services market.

  ## Market Position

  TechCorp holds 15% market share. MegaTech dominates with 40%.
  RegulatoryCo oversees the industry with strict data privacy rules.
  """

  defp mock_llm_fn do
    fn request ->
      all_content = Enum.map_join(request.messages, " ", & &1.content)

      cond do
        String.contains?(all_content, "Extract entities") ->
          {:ok,
           %{
             content:
               Jason.encode!(%{
                 entities: [
                   %{
                     id: "techcorp",
                     type: "company",
                     name: "TechCorp",
                     properties: %{employees: 500}
                   },
                   %{id: "megatech", type: "company", name: "MegaTech", properties: %{}},
                   %{id: "regulatoryco", type: "company", name: "RegulatoryCo", properties: %{}}
                 ],
                 relationships: [
                   %{from: "techcorp", to: "megatech", type: "competitor", weight: 0.8}
                 ]
               })
           }}

        String.contains?(all_content, "Generate") ->
          {:ok,
           %{
             content:
               Jason.encode!(%{
                 personas: [
                   %{
                     name: "Alice Chen",
                     role: "CTO",
                     backstory: "Tech visionary",
                     domain: "technology",
                     traits: %{
                       openness: 0.8,
                       conscientiousness: 0.7,
                       extraversion: 0.6,
                       agreeableness: 0.5,
                       neuroticism: 0.3,
                       risk_tolerance: 0.7,
                       innovation_bias: 0.8,
                       consensus_seeking: 0.4,
                       analytical_depth: 0.7,
                       emotional_reactivity: 0.3,
                       authority_deference: 0.2,
                       competitive_drive: 0.6
                     }
                   }
                 ]
               })
           }}

        true ->
          {:ok, %{content: "{}"}}
      end
    end
  end

  describe "parse/2" do
    test "parses seed content into world model with mock LLM" do
      {:ok, result} = SeedParser.parse(@sample_seed, llm_fn: mock_llm_fn(), agent_count: 1)

      assert length(result.entities) == 3
      assert length(result.relationships) == 1
      assert length(result.personas) == 1

      [persona] = result.personas
      assert persona.name == "Alice Chen"
      assert persona.role == "CTO"
      assert persona.traits.openness == 0.8
    end

    test "chunks are returned from parsing" do
      {:ok, result} = SeedParser.parse(@sample_seed, llm_fn: mock_llm_fn())

      assert length(result.chunks) > 0
    end
  end

  describe "parse_content/2" do
    test "parses markdown content into chunks" do
      {:ok, chunks} = SeedParser.parse_content(@sample_seed, ".md")
      assert length(chunks) > 0
    end
  end
end
