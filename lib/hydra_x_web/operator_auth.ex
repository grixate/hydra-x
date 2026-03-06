defmodule HydraXWeb.OperatorAuth do
  @moduledoc false

  import Plug.Conn
  import Phoenix.Controller

  alias Phoenix.Component
  alias Phoenix.LiveView
  alias HydraX.Runtime

  @session_key :operator_authenticated

  def init(action), do: action

  def call(conn, :redirect_if_authenticated) do
    if Runtime.operator_password_configured?() and authenticated?(conn) do
      conn
      |> redirect(to: "/")
      |> halt()
    else
      conn
    end
  end

  def call(conn, :require_authenticated_operator) do
    if Runtime.operator_password_configured?() and not authenticated?(conn) do
      conn
      |> put_flash(:error, "Sign in to access the Hydra-X control plane.")
      |> redirect(to: "/login")
      |> halt()
    else
      conn
    end
  end

  def log_in(conn) do
    conn
    |> configure_session(renew: true)
    |> put_session(@session_key, true)
  end

  def log_out(conn) do
    conn
    |> configure_session(renew: true)
    |> delete_session(@session_key)
  end

  def authenticated?(conn), do: get_session(conn, @session_key) == true

  def on_mount(:require_authenticated_operator, _params, session, socket) do
    configured? = Runtime.operator_password_configured?()
    authenticated? = Map.get(session, Atom.to_string(@session_key)) == true

    cond do
      not configured? ->
        {:cont, Component.assign(socket, :operator_authenticated, false)}

      authenticated? ->
        {:cont, Component.assign(socket, :operator_authenticated, true)}

      true ->
        {:halt,
         socket
         |> LiveView.put_flash(:error, "Sign in to access the Hydra-X control plane.")
         |> LiveView.redirect(to: "/login")}
    end
  end
end
