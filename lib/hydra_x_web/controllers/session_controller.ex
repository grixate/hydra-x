defmodule HydraXWeb.SessionController do
  use HydraXWeb, :controller

  alias HydraX.Runtime
  alias HydraX.Runtime.OperatorSecret
  alias HydraXWeb.OperatorAuth

  def new(conn, _params) do
    render(conn, :new,
      password_configured?: Runtime.operator_password_configured?(),
      changeset: OperatorSecret.changeset(%OperatorSecret{}, %{})
    )
  end

  def create(conn, %{"operator_secret" => params}) do
    case Runtime.authenticate_operator(params["password"] || "") do
      :ok ->
        conn
        |> OperatorAuth.log_in()
        |> put_flash(:info, "Signed in.")
        |> redirect(to: "/")

      {:error, :not_configured} ->
        conn
        |> put_flash(:info, "No operator password is configured yet. Set one on /setup.")
        |> redirect(to: "/setup")

      {:error, :unauthorized} ->
        render(conn, :new,
          password_configured?: true,
          changeset:
            OperatorSecret.changeset(%OperatorSecret{}, %{})
            |> Ecto.Changeset.add_error(:password, "is invalid")
        )
    end
  end

  def delete(conn, _params) do
    conn
    |> OperatorAuth.log_out()
    |> put_flash(:info, "Signed out.")
    |> redirect(to: "/login")
  end
end
