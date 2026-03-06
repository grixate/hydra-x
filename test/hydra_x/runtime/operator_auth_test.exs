defmodule HydraX.Runtime.OperatorAuthTest do
  use HydraX.DataCase

  alias HydraX.Runtime

  test "operator password can be stored and authenticated" do
    refute Runtime.operator_password_configured?()
    assert {:error, :not_configured} = Runtime.authenticate_operator("wrong")

    assert {:ok, secret} =
             Runtime.save_operator_secret_password(%{
               "password" => "hydra-password-123",
               "password_confirmation" => "hydra-password-123"
             })

    assert secret.password_hash
    assert secret.password_salt
    assert Runtime.operator_password_configured?()
    assert :ok = Runtime.authenticate_operator("hydra-password-123")
    assert {:error, :unauthorized} = Runtime.authenticate_operator("bad-password")
  end
end
