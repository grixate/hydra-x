defmodule HydraX.Product.Pricing do
  @moduledoc """
  Model pricing table — cents per 1M tokens.
  """

  @model_pricing %{
    "claude-sonnet-4" => %{input: 300, output: 1500},
    "claude-sonnet-4-6" => %{input: 300, output: 1500},
    "claude-haiku-4" => %{input: 25, output: 125},
    "claude-haiku-4-5" => %{input: 25, output: 125},
    "claude-opus-4" => %{input: 1500, output: 7500},
    "claude-opus-4-6" => %{input: 1500, output: 7500},
    "gpt-4o" => %{input: 250, output: 1000},
    "gpt-4o-mini" => %{input: 15, output: 60},
    "text-embedding-3-small" => %{input: 2, output: 0},
    "text-embedding-3-large" => %{input: 13, output: 0},
    "default" => %{input: 300, output: 1500}
  }

  def cost_cents(model, tokens_in, tokens_out) do
    pricing = Map.get(@model_pricing, to_string(model), @model_pricing["default"])
    input_cost = tokens_in * pricing.input / 1_000_000
    output_cost = tokens_out * pricing.output / 1_000_000
    round(input_cost + output_cost)
  end
end
