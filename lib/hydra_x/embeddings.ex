defmodule HydraX.Embeddings do
  @moduledoc """
  Embedding facade for local and OpenAI-compatible memory vectors.

  Hydra-X defaults to a local deterministic backend so memory recall stays
  self-contained. When configured, it can also call an OpenAI-compatible
  embeddings endpoint and persist the resulting vectors on memory metadata.
  """

  alias HydraX.Config

  @default_backend "local_hash_v1"
  @default_dimensions 64

  def embed(input, opts \\ []) do
    text =
      input
      |> normalize_input()
      |> Enum.join(" ")
      |> String.trim()

    requested_backend = backend(opts)

    if text == "" do
      {:ok,
       %{
         backend: requested_backend,
         model: model(opts, requested_backend),
         dimensions: dimensions(opts),
         vector: []
       }}
    else
      do_embed(text, requested_backend, opts)
    end
  end

  def status(opts \\ []) do
    configured_backend = backend(opts)
    active_backend = active_backend(configured_backend, opts)
    configured_model = model(opts, configured_backend)

    %{
      configured_backend: configured_backend,
      active_backend: active_backend,
      configured_model: configured_model,
      active_model: model(opts, active_backend),
      fallback_enabled?: Keyword.get(opts, :allow_fallback, true),
      fallback_backend: if(configured_backend == "openai_compatible", do: @default_backend),
      url_configured?: present?(Keyword.get(opts, :url, Config.embedding_url())),
      api_key_configured?: present?(Keyword.get(opts, :api_key, Config.embedding_api_key())),
      degraded?: configured_backend != active_backend
    }
  end

  def cosine_similarity([], _right), do: 0.0
  def cosine_similarity(_left, []), do: 0.0

  def cosine_similarity(left, right) when is_list(left) and is_list(right) do
    if length(left) != length(right) do
      0.0
    else
      Enum.zip(left, right)
      |> Enum.reduce(0.0, fn {a, b}, acc -> acc + a * b end)
      |> Float.round(6)
    end
  end

  def cosine_similarity(_left, _right), do: 0.0

  defp do_embed(text, "openai_compatible" = requested_backend, opts) do
    case openai_compatible_embed(text, opts) do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} ->
        if Keyword.get(opts, :allow_fallback, true) do
          {:ok,
           local_result(text, opts)
           |> Map.put(:fallback_from, requested_backend)
           |> Map.put(:fallback_reason, inspect(reason))}
        else
          {:error, reason}
        end
    end
  end

  defp do_embed(text, _backend, opts), do: {:ok, local_result(text, opts)}

  defp local_result(text, opts) do
    backend = @default_backend
    dimensions = Keyword.get(opts, :dimensions, @default_dimensions)

    %{
      backend: backend,
      model: backend,
      dimensions: dimensions,
      vector: local_hash_vector(text, dimensions)
    }
  end

  defp openai_compatible_embed(text, opts) do
    url = Keyword.get(opts, :url, Config.embedding_url())
    api_key = Keyword.get(opts, :api_key, Config.embedding_api_key())
    model = model(opts, "openai_compatible")

    cond do
      not is_binary(url) or url == "" ->
        {:error, :missing_embedding_url}

      not is_binary(api_key) or api_key == "" ->
        {:error, :missing_embedding_api_key}

      true ->
        request_fn =
          Keyword.get(opts, :request_fn) ||
            Application.get_env(:hydra_x, :embedding_request_fn) ||
            (&Req.post/1)

        headers = [
          {"authorization", "Bearer #{api_key}"},
          {"content-type", "application/json"},
          {"accept", "application/json"}
        ]

        body = %{model: model, input: text}

        case request_fn.(url: url, headers: headers, json: body) do
          {:ok, %{status: status, body: %{"data" => [first | _]}}} when status in 200..299 ->
            vector = first["embedding"] || []

            {:ok,
             %{
               backend: "openai_compatible",
               model: model,
               dimensions: length(vector),
               vector: vector
             }}

          {:ok, %{status: status}} ->
            {:error, {:http_status, status}}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp backend(opts), do: Keyword.get(opts, :backend, Config.embedding_backend())
  defp dimensions(opts), do: Keyword.get(opts, :dimensions, @default_dimensions)

  defp model(opts, "openai_compatible"),
    do: Keyword.get(opts, :model, Config.embedding_model())

  defp model(_opts, backend), do: backend

  defp active_backend("openai_compatible", opts) do
    if present?(Keyword.get(opts, :url, Config.embedding_url())) and
         present?(Keyword.get(opts, :api_key, Config.embedding_api_key())) do
      "openai_compatible"
    else
      @default_backend
    end
  end

  defp active_backend(backend, _opts), do: backend

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false

  defp normalize_input(value) when is_binary(value) do
    value
    |> String.downcase()
    |> String.split(~r/[^a-z0-9]+/u, trim: true)
    |> Enum.reject(&(String.length(&1) < 2))
    |> add_bigrams()
  end

  defp normalize_input(value) when is_list(value) do
    value
    |> Enum.map(&to_string/1)
    |> Enum.join(" ")
    |> normalize_input()
  end

  defp normalize_input(_value), do: []

  defp add_bigrams(tokens) do
    bigrams =
      tokens
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(&Enum.join(&1, "_"))

    Enum.uniq(tokens ++ bigrams)
  end

  defp local_hash_vector(text, dimensions) do
    terms = normalize_input(text)

    weighted =
      Enum.reduce(terms, List.duplicate(0.0, dimensions), fn term, acc ->
        index = :erlang.phash2(term, dimensions)
        sign = if rem(:erlang.phash2("sign:" <> term, 2), 2) == 0, do: 1.0, else: -1.0
        weight = 1.0 + min(String.length(term), 12) / 12
        List.update_at(acc, index, &(&1 + sign * weight))
      end)

    normalize(weighted)
  end

  defp normalize(values) do
    magnitude =
      values
      |> Enum.reduce(0.0, fn value, acc -> acc + value * value end)
      |> :math.sqrt()

    if magnitude == 0.0 do
      []
    else
      Enum.map(values, &Float.round(&1 / magnitude, 6))
    end
  end
end
