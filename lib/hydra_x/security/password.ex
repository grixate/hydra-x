defmodule HydraX.Security.Password do
  @moduledoc """
  PBKDF2-based password hashing for the operator control plane.
  """

  @iterations 120_000
  @length 32
  @digest :sha256

  def hash_password(password) when is_binary(password) do
    salt = :crypto.strong_rand_bytes(16)
    hash = pbkdf2(password, salt)

    %{
      salt: Base.encode64(salt, padding: false),
      hash: Base.encode64(hash, padding: false)
    }
  end

  def verify_password(password, encoded_salt, encoded_hash)
      when is_binary(password) and is_binary(encoded_salt) and is_binary(encoded_hash) do
    with {:ok, salt} <- Base.decode64(encoded_salt, padding: false),
         {:ok, expected_hash} <- Base.decode64(encoded_hash, padding: false) do
      candidate_hash = pbkdf2(password, salt)

      if byte_size(candidate_hash) == byte_size(expected_hash) do
        Plug.Crypto.secure_compare(candidate_hash, expected_hash)
      else
        false
      end
    else
      :error -> false
    end
  end

  defp pbkdf2(password, salt) do
    :crypto.pbkdf2_hmac(@digest, password, salt, @iterations, @length)
  end
end
