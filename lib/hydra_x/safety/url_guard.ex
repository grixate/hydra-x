defmodule HydraX.Safety.UrlGuard do
  @moduledoc """
  Basic outbound URL validation to reduce SSRF risk.
  """

  @blocked_hosts ~w(localhost metadata.google.internal host.docker.internal)

  def validate_outbound_url(url) when is_binary(url) do
    uri = URI.parse(String.trim(url))

    cond do
      uri.scheme not in ["http", "https"] -> {:error, :unsupported_scheme}
      is_nil(uri.host) or uri.host == "" -> {:error, :missing_host}
      blocked_host?(uri.host) -> {:error, :blocked_host}
      private_ip_literal?(uri.host) -> {:error, :private_address}
      true -> {:ok, uri}
    end
  end

  def validate_outbound_url(_url), do: {:error, :invalid_url}

  defp blocked_host?(host) do
    host in @blocked_hosts or String.ends_with?(host, ".local") or
      String.ends_with?(host, ".internal")
  end

  defp private_ip_literal?(host) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, {127, _, _, _}} -> true
      {:ok, {10, _, _, _}} -> true
      {:ok, {172, second, _, _}} when second in 16..31 -> true
      {:ok, {192, 168, _, _}} -> true
      {:ok, {169, 254, _, _}} -> true
      {:ok, {0, _, _, _}} -> true
      {:ok, _ipv6} -> true
      {:error, _reason} -> false
    end
  end
end
