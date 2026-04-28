defmodule HydraXWeb.InvitationController do
  use HydraXWeb, :controller

  alias HydraX.Accounts
  alias HydraXWeb.Plugs.UserAuth

  def edit(conn, %{"token" => token}) do
    render(conn, :edit,
      token: token,
      form: to_form(Accounts.change_user_registration(), as: :user)
    )
  end

  def update(conn, %{"token" => token, "user" => params}) do
    case Accounts.register_invited_user(token, params) do
      {:ok, %{user: user}} ->
        conn
        |> UserAuth.put_user_session(user)
        |> put_flash(:info, "Invitation accepted.")
        |> redirect(to: ~p"/product")

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :edit, token: token, form: to_form(changeset, as: :user))

      {:error, :invitation_invalid} ->
        conn
        |> put_flash(:error, "Invitation link is invalid or expired.")
        |> redirect(to: ~p"/login")
    end
  end
end
