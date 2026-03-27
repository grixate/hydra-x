defmodule HydraX.Simulation.Config do
  @moduledoc """
  Simulation configuration schema.

  Defines all tunable parameters for a simulation run, including tick count,
  budget caps, LLM tier configuration, world parameters, and decision router tuning.
  """

  @type t :: %__MODULE__{
          name: String.t(),
          max_ticks: pos_integer(),
          tick_interval_ms: non_neg_integer(),
          agent_count: pos_integer(),
          max_budget_cents: pos_integer(),
          rng_seed: integer() | nil,
          cheap_provider: atom(),
          cheap_model: String.t(),
          frontier_provider: atom(),
          frontier_model: String.t(),
          ollama_fallback: boolean(),
          ollama_model: String.t(),
          event_frequency: float(),
          crisis_probability: float(),
          market_volatility: float(),
          novelty_threshold: pos_integer(),
          stakes_threshold: float(),
          emotional_reactivity_floor: float()
        }

  defstruct name: "Untitled Simulation",
            max_ticks: 40,
            tick_interval_ms: 500,
            agent_count: 20,
            max_budget_cents: 50,
            rng_seed: nil,
            cheap_provider: :openai_compatible,
            cheap_model: "deepseek-chat",
            frontier_provider: :anthropic,
            frontier_model: "claude-sonnet-4-20250514",
            ollama_fallback: true,
            ollama_model: "llama3.1:8b",
            event_frequency: 0.3,
            crisis_probability: 0.05,
            market_volatility: 0.5,
            novelty_threshold: 2,
            stakes_threshold: 0.7,
            emotional_reactivity_floor: 0.5

  @doc """
  Build a config from a map of attributes.
  """
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    struct(__MODULE__, attrs)
  end

  @doc """
  Calculate the per-tick budget limit in cents.
  """
  @spec per_tick_budget(t()) :: float()
  def per_tick_budget(%__MODULE__{max_budget_cents: total, max_ticks: ticks}) do
    total / ticks
  end

  @doc """
  Validate configuration, returning {:ok, config} or {:error, reasons}.
  """
  @spec validate(t()) :: {:ok, t()} | {:error, [String.t()]}
  def validate(%__MODULE__{} = config) do
    errors =
      []
      |> validate_positive(:max_ticks, config.max_ticks)
      |> validate_positive(:agent_count, config.agent_count)
      |> validate_positive(:max_budget_cents, config.max_budget_cents)
      |> validate_range(:event_frequency, config.event_frequency, 0.0, 1.0)
      |> validate_range(:crisis_probability, config.crisis_probability, 0.0, 1.0)
      |> validate_range(:market_volatility, config.market_volatility, 0.0, 1.0)
      |> validate_range(:stakes_threshold, config.stakes_threshold, 0.0, 1.0)

    case errors do
      [] -> {:ok, config}
      errs -> {:error, Enum.reverse(errs)}
    end
  end

  defp validate_positive(errors, _field, value) when is_number(value) and value > 0, do: errors

  defp validate_positive(errors, field, _value),
    do: ["#{field} must be a positive number" | errors]

  defp validate_range(errors, _field, value, min, max)
       when is_number(value) and value >= min and value <= max,
       do: errors

  defp validate_range(errors, field, _value, min, max),
    do: ["#{field} must be between #{min} and #{max}" | errors]
end
