defmodule HydraX.Simulation.Agent.Persona do
  @moduledoc """
  Persona definition struct and archetype builder.

  A persona defines who a simulated agent is — their name, role, backstory,
  and personality trait vector. Archetypes provide pre-built persona templates
  for common business simulation roles.
  """

  alias HydraX.Simulation.Agent.Traits

  @type t :: %__MODULE__{
          name: String.t(),
          role: String.t(),
          backstory: String.t(),
          traits: Traits.t(),
          domain: atom() | nil
        }

  defstruct name: "Unknown",
            role: "Participant",
            backstory: "",
            traits: %Traits{},
            domain: nil

  @doc """
  Create a new persona with the given attributes.
  """
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    traits =
      case Map.get(attrs, :traits, Map.get(attrs, "traits")) do
        %Traits{} = t -> t
        map when is_map(map) -> struct(Traits, map)
        nil -> %Traits{}
      end

    %__MODULE__{
      name: Map.get(attrs, :name, Map.get(attrs, "name", "Unknown")),
      role: Map.get(attrs, :role, Map.get(attrs, "role", "Participant")),
      backstory: Map.get(attrs, :backstory, Map.get(attrs, "backstory", "")),
      traits: traits,
      domain: Map.get(attrs, :domain, Map.get(attrs, "domain"))
    }
  end

  @doc """
  Returns a pre-built persona archetype.
  """
  @spec archetype(atom()) :: t()
  def archetype(:cautious_cfo) do
    %__MODULE__{
      name: "CFO",
      role: "Chief Financial Officer",
      backstory:
        "Conservative financial leader focused on risk management and fiscal discipline.",
      domain: :finance,
      traits: %Traits{
        risk_tolerance: 0.2,
        conscientiousness: 0.9,
        analytical_depth: 0.9,
        consensus_seeking: 0.6,
        neuroticism: 0.5,
        competitive_drive: 0.3,
        innovation_bias: 0.2,
        authority_deference: 0.4,
        openness: 0.3,
        agreeableness: 0.5,
        extraversion: 0.3,
        emotional_reactivity: 0.3
      }
    }
  end

  def archetype(:visionary_ceo) do
    %__MODULE__{
      name: "CEO",
      role: "Chief Executive Officer",
      backstory:
        "Bold visionary leader who drives innovation and takes calculated risks to achieve growth.",
      domain: :leadership,
      traits: %Traits{
        risk_tolerance: 0.8,
        conscientiousness: 0.6,
        analytical_depth: 0.5,
        consensus_seeking: 0.3,
        neuroticism: 0.3,
        competitive_drive: 0.9,
        innovation_bias: 0.9,
        authority_deference: 0.1,
        openness: 0.9,
        agreeableness: 0.4,
        extraversion: 0.8,
        emotional_reactivity: 0.4
      }
    }
  end

  def archetype(:pragmatic_ops_director) do
    %__MODULE__{
      name: "Ops Director",
      role: "Operations Director",
      backstory: "Practical operations leader who balances efficiency with team consensus.",
      domain: :operations,
      traits: %Traits{
        risk_tolerance: 0.4,
        conscientiousness: 0.8,
        analytical_depth: 0.7,
        consensus_seeking: 0.7,
        neuroticism: 0.4,
        competitive_drive: 0.5,
        innovation_bias: 0.4,
        authority_deference: 0.6,
        openness: 0.5,
        agreeableness: 0.6,
        extraversion: 0.5,
        emotional_reactivity: 0.3
      }
    }
  end

  def archetype(:aggressive_competitor) do
    %__MODULE__{
      name: "Competitor CEO",
      role: "Competitor CEO",
      backstory: "Aggressive market disruptor who prioritizes winning over relationships.",
      domain: :leadership,
      traits: %Traits{
        risk_tolerance: 0.9,
        conscientiousness: 0.5,
        analytical_depth: 0.4,
        consensus_seeking: 0.1,
        neuroticism: 0.4,
        competitive_drive: 1.0,
        innovation_bias: 0.7,
        authority_deference: 0.0,
        openness: 0.6,
        agreeableness: 0.1,
        extraversion: 0.9,
        emotional_reactivity: 0.6
      }
    }
  end

  def archetype(:cautious_regulator) do
    %__MODULE__{
      name: "Regulator",
      role: "Regulatory Officer",
      backstory:
        "Rule-following regulatory officer who prioritizes compliance, stability, and due process.",
      domain: :regulation,
      traits: %Traits{
        openness: 0.3,
        conscientiousness: 0.9,
        extraversion: 0.4,
        agreeableness: 0.5,
        neuroticism: 0.6,
        risk_tolerance: 0.1,
        innovation_bias: 0.1,
        consensus_seeking: 0.5,
        analytical_depth: 0.8,
        emotional_reactivity: 0.4,
        authority_deference: 0.8,
        competitive_drive: 0.2
      }
    }
  end

  def archetype(:maverick_founder) do
    %__MODULE__{
      name: "Founder",
      role: "Founder & CEO",
      backstory:
        "Chaotic visionary founder who bets big on instinct, ignores hierarchy, and innovates relentlessly.",
      domain: :leadership,
      traits: %Traits{
        openness: 1.0,
        conscientiousness: 0.4,
        extraversion: 0.9,
        agreeableness: 0.3,
        neuroticism: 0.5,
        risk_tolerance: 0.9,
        innovation_bias: 1.0,
        consensus_seeking: 0.1,
        analytical_depth: 0.3,
        emotional_reactivity: 0.7,
        authority_deference: 0.0,
        competitive_drive: 0.8
      }
    }
  end

  @doc """
  Returns a list of all available archetype names.
  """
  @spec archetypes() :: [atom()]
  def archetypes do
    [
      :cautious_cfo,
      :visionary_ceo,
      :pragmatic_ops_director,
      :aggressive_competitor,
      :cautious_regulator,
      :maverick_founder
    ]
  end

  @doc """
  Map a domain to a role category for the relevance lookup table (spec §4.1).
  """
  @spec role_category(atom() | nil) :: atom()
  def role_category(domain) do
    case domain do
      :finance -> :finance
      :operations -> :operations
      :leadership -> :c_suite
      :technology -> :operations
      :marketing -> :c_suite
      :regulation -> :regulator
      nil -> :c_suite
      _ -> :c_suite
    end
  end
end
