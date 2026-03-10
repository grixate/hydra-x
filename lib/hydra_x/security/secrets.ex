defmodule HydraX.Security.Secrets do
  @moduledoc """
  Transparent encryption helpers for persisted runtime secrets.

  Values are stored as `enc:v1:<iv>:<tag>:<ciphertext>` and decrypted on read.
  Legacy plaintext values are still readable and can be re-encrypted on the next save.
  """

  @prefix "enc"
  @version "v1"

  alias HydraX.Config

  def encrypt(nil), do: nil
  def encrypt(""), do: ""

  def encrypt(value) when is_binary(value) do
    iv = :crypto.strong_rand_bytes(12)
    key = key_bytes()
    {ciphertext, tag} = :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, value, "", true)

    Enum.join(
      [
        @prefix,
        @version,
        Base.url_encode64(iv, padding: false),
        Base.url_encode64(tag, padding: false),
        Base.url_encode64(ciphertext, padding: false)
      ],
      ":"
    )
  end

  def decrypt(nil), do: nil
  def decrypt(""), do: ""

  def decrypt(value) when is_binary(value) do
    case String.split(value, ":", parts: 5) do
      [@prefix, @version, iv, tag, ciphertext] ->
        key = key_bytes()

        with {:ok, iv} <- Base.url_decode64(iv, padding: false),
             {:ok, tag} <- Base.url_decode64(tag, padding: false),
             {:ok, ciphertext} <- Base.url_decode64(ciphertext, padding: false) do
          :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, ciphertext, "", tag, false)
        else
          _ -> value
        end

      _ ->
        value
    end
  rescue
    _ -> value
  end

  def encrypted?(value) when is_binary(value),
    do: String.starts_with?(value, @prefix <> ":" <> @version <> ":")

  def encrypted?(_value), do: false

  def decrypt_fields(struct, fields) do
    Enum.reduce(fields, struct, fn field, acc ->
      Map.put(acc, field, decrypt(Map.get(acc, field)))
    end)
  end

  def encrypt_secret_attrs(attrs, existing, fields) when is_map(attrs) do
    Enum.reduce(fields, attrs, fn field, acc ->
      string_key = to_string(field)
      existing_value = Map.get(existing, field)

      case Map.get(acc, string_key, Map.get(acc, field)) do
        nil ->
          acc

        "" ->
          acc
          |> Map.put(string_key, encrypt(existing_value))
          |> Map.delete(field)

        value when is_binary(value) ->
          acc
          |> Map.put(string_key, encrypt(value))
          |> Map.delete(field)

        _value ->
          acc
      end
    end)
  end

  def key_source do
    cond do
      System.get_env("HYDRA_X_SECRET_KEY") not in [nil, ""] -> :env
      Config.endpoint_secret_key_base() not in [nil, ""] -> :endpoint
      true -> :missing
    end
  end

  defp key_bytes do
    Config.secret_key()
    |> to_string()
    |> then(&:crypto.hash(:sha256, &1))
  end
end
