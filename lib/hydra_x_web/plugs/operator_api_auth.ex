defmodule HydraXWeb.Plugs.OperatorAPIAuth do
  @moduledoc false

  import Plug.Conn
  import Phoenix.Controller

  alias HydraXWeb.OperatorAuth

  def init(opts), do: opts

  def call(conn, _opts) do
    if not OperatorAuth.session_state(conn).valid? do
      conn
      |> put_status(:unauthorized)
      |> json(%{error: "operator_auth_required"})
      |> halt()
    else
      conn
    end
  end
end
