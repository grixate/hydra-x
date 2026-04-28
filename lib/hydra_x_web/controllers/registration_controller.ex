defmodule HydraXWeb.RegistrationController do
  use HydraXWeb, :controller

  alias HydraX.Accounts
  alias HydraXWeb.OperatorAuth

  def new(conn, _params) do
    if Accounts.operator_user_exists?() do
      conn
      |> put_flash(:error, "Registration is closed. Ask an operator for an invitation.")
      |> redirect(to: ~p"/login")
    else
      render(conn, :new, form: to_form(Accounts.change_user_registration(), as: :user))
    end
  end

  def create(conn, %{"user" => params}) do
    case Accounts.register_first_operator(params) do
      {:ok, %{user: user}} ->
        conn
        |> OperatorAuth.log_in(user)
        |> put_flash(:info, "Operator account created.")
        |> redirect(to: ~p"/setup")

      {:error, :registration_closed} ->
        conn
        |> put_flash(:error, "Registration is closed. Ask an operator for an invitation.")
        |> redirect(to: ~p"/login")

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :new, form: to_form(changeset, as: :user))
    end
  end
end
