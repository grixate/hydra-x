defmodule HydraXWeb.Plugs.APIOriginCheck do
  @moduledoc """
  Stream A4.2 — CSRF mitigation for cookie-authenticated `/api/v1/*`
  endpoints.

  The SPA sends requests with `credentials: "include"` so the session
  cookie rides along. Standard Phoenix CSRF tokens aren't used on the
  JSON API, leaving state-changing requests exposed to cross-origin
  form submissions.

  This plug enforces a same-origin check on POST/PATCH/DELETE: the
  `Origin` header must match the request's own host (or one of the
  allow-listed hosts in `:hydra_x, :api_allowed_origins`).

  Safe methods (GET / HEAD / OPTIONS) pass through. Requests missing
  the `Origin` header pass through too — same-origin `fetch` omits it
  in many browsers; `SameSite=Lax` cookies still gate cross-site form
  submissions at the cookie layer.
  """

  import Plug.Conn

  @safe_methods ~w(GET HEAD OPTIONS)

  def init(opts), do: opts

  def call(%Plug.Conn{method: method} = conn, _opts) when method in @safe_methods, do: conn

  def call(%Plug.Conn{} = conn, _opts) do
    case origin_header(conn) do
      nil ->
        conn

      origin ->
        if origin_allowed?(conn, origin) do
          conn
        else
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(403, Jason.encode!(%{error: "forbidden_origin", origin: origin}))
          |> halt()
        end
    end
  end

  defp origin_header(conn) do
    case get_req_header(conn, "origin") do
      [origin | _] -> origin
      _ -> nil
    end
  end

  defp origin_allowed?(conn, origin) do
    allowed = [expected_origin(conn) | configured_origins()] |> Enum.reject(&is_nil/1)
    Enum.any?(allowed, &origins_match?(origin, &1))
  end

  defp expected_origin(conn) do
    scheme = Atom.to_string(conn.scheme || :http)
    host = conn.host || "localhost"
    port = conn.port

    default_port? =
      (scheme == "http" and port in [80, nil]) or
        (scheme == "https" and port in [443, nil])

    host_part = if default_port?, do: host, else: "#{host}:#{port}"
    "#{scheme}://#{host_part}"
  end

  defp configured_origins do
    Application.get_env(:hydra_x, :api_allowed_origins, []) |> List.wrap()
  end

  defp origins_match?(origin, allowed) do
    String.downcase(to_string(origin)) == String.downcase(to_string(allowed))
  end
end
