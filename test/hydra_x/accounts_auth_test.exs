defmodule HydraX.AccountsAuthTest do
  use HydraX.DataCase

  alias HydraX.Accounts
  alias HydraX.Accounts.User

  defp operator_attrs(attrs \\ %{}) do
    attrs = Map.new(attrs)

    email =
      Map.get(attrs, :email, "operator+#{System.unique_integer([:positive])}@test.example.com")

    password = Map.get(attrs, :password, "hydra-password-123")

    %{
      "email" => email,
      "display_name" => Map.get(attrs, :display_name, "Operator"),
      "password" => password,
      "password_confirmation" => password
    }
  end

  test "register_first_operator creates an operator user with a hashed password and workspace" do
    assert {:ok, %{user: %User{} = user, workspace: workspace, membership: membership}} =
             Accounts.register_first_operator(operator_attrs())

    assert Accounts.operator?(user)
    assert user.password_hash
    refute user.password_hash =~ "hydra-password"
    assert workspace.created_by_user_id == user.id
    assert membership.role == "owner"
    assert Accounts.operator_user_exists?()
  end

  test "public registration closes after the first operator" do
    assert {:ok, _} = Accounts.register_first_operator(operator_attrs())

    assert {:error, :registration_closed} =
             Accounts.register_first_operator(
               operator_attrs(email: "second@test.example.com", display_name: "Second")
             )
  end

  test "authenticate_user validates email and password" do
    password = "hydra-password-123"
    attrs = operator_attrs(email: "auth@test.example.com", password: password)
    assert {:ok, %{user: user}} = Accounts.register_first_operator(attrs)

    assert {:ok, authed} = Accounts.authenticate_user(user.email, password)
    assert authed.id == user.id
    assert authed.last_sign_in_at
    assert {:error, :invalid_credentials} = Accounts.authenticate_user(user.email, "bad-password")
  end

  test "password reset tokens update password once" do
    old_password = "hydra-password-123"
    new_password = "hydra-password-456"
    attrs = operator_attrs(email: "reset@test.example.com", password: old_password)
    assert {:ok, %{user: user}} = Accounts.register_first_operator(attrs)
    assert {:ok, _token, raw_token} = Accounts.issue_password_reset(user.email)

    assert {:ok, updated} =
             Accounts.reset_user_password(raw_token, %{
               "password" => new_password,
               "password_confirmation" => new_password
             })

    assert updated.id == user.id
    assert {:ok, _user} = Accounts.authenticate_user(user.email, new_password)
    assert {:error, :invalid_credentials} = Accounts.authenticate_user(user.email, old_password)
    assert {:error, :invalid_or_expired} = Accounts.reset_user_password(raw_token, %{})
  end

  test "invitation registration creates a local password account and membership" do
    assert {:ok, %{user: operator, workspace: workspace}} =
             Accounts.register_first_operator(operator_attrs())

    assert {:ok, _invitation, raw_token} =
             Accounts.create_invitation(workspace, %{
               "email" => "member@test.example.com",
               "invited_by_user_id" => operator.id,
               "role" => "member"
             })

    assert {:ok, %{user: member}} =
             Accounts.register_invited_user(raw_token, %{
               "display_name" => "Member",
               "password" => "hydra-password-789",
               "password_confirmation" => "hydra-password-789"
             })

    refute Accounts.operator?(member)
    assert {:ok, authed} = Accounts.authenticate_user(member.email, "hydra-password-789")
    assert authed.id == member.id
    assert Accounts.workspace_member?(workspace.id, member.id)
  end
end
