defmodule HydraXWeb.DevAuth do
  @moduledoc false

  import Ecto.Query

  alias HydraX.Accounts
  alias HydraX.Accounts.User
  alias HydraX.Repo

  @dev_email "dev@hydra.local"
  @dev_password "hydra-dev-password-123"

  def enabled? do
    Application.get_env(:hydra_x, :env) == :dev and
      Application.get_env(:hydra_x, :dev_auth_bypass, false) == true
  end

  def operator_user! do
    unless enabled?() do
      raise ArgumentError, "development auth bypass is only available in dev"
    end

    first_operator_user() || create_or_promote_dev_operator!()
  end

  defp first_operator_user do
    Repo.one(
      from u in User,
        where: not is_nil(u.operator_at),
        order_by: [asc: u.inserted_at],
        limit: 1
    )
  end

  defp create_or_promote_dev_operator! do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    case Accounts.get_user_by_email(@dev_email) do
      %User{} = user ->
        user
        |> User.operator_changeset(now)
        |> Ecto.Changeset.put_change(:email_verified_at, user.email_verified_at || now)
        |> Repo.update!()

      nil ->
        case Accounts.register_first_operator(%{
               "email" => @dev_email,
               "display_name" => "Development Operator",
               "password" => @dev_password,
               "password_confirmation" => @dev_password
             }) do
          {:ok, %{user: user}} ->
            user

          {:error, :registration_closed} ->
            first_operator_user() ||
              raise "development auth bypass could not find the existing operator"

          {:error, reason} ->
            raise "development auth bypass could not create operator: #{inspect(reason)}"
        end
    end
  end
end
