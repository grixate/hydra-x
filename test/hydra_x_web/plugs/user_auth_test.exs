defmodule HydraXWeb.Plugs.UserAuthTest do
  use HydraXWeb.ConnCase, async: false

  alias HydraX.Accounts
  alias HydraXWeb.Plugs.UserAuth

  defp make_user! do
    email = "auth+#{System.unique_integer([:positive])}@test.example.com"

    {:ok, %{user: user}} =
      Accounts.create_user_with_workspace(%{"email" => email, "display_name" => "T"})

    user
  end

  defp prime_session(conn) do
    conn
    |> Plug.Test.init_test_session(%{})
    |> UserAuth.call([])
  end

  test "call/2 assigns nil current_user when no session" do
    conn = prime_session(build_conn())
    assert conn.assigns[:current_user] == nil
  end

  test "put_user_session + call round-trips the user" do
    user = make_user!()

    conn =
      build_conn()
      |> Plug.Test.init_test_session(%{})
      |> UserAuth.put_user_session(user)

    # Mint a fresh conn with the same session cookie simulated inline.
    session = Plug.Conn.get_session(conn)

    conn2 =
      build_conn()
      |> Plug.Test.init_test_session(session)
      |> UserAuth.call([])

    assert conn2.assigns[:current_user].id == user.id
  end

  test "call/2 clears session and assigns nil when user_id no longer resolves" do
    conn =
      build_conn()
      |> Plug.Test.init_test_session(%{})
      |> Plug.Conn.fetch_session()
      |> Plug.Conn.put_session(:hydra_user_id, Ecto.UUID.generate())
      |> UserAuth.call([])

    assert conn.assigns[:current_user] == nil
    # Session should no longer carry the stale user id.
    assert Plug.Conn.get_session(conn, :hydra_user_id) == nil
  end

  test "require_user/2 halts with 401 when no user is loaded" do
    conn =
      build_conn()
      |> Plug.Test.init_test_session(%{})
      |> UserAuth.call([])
      |> UserAuth.require_user([])

    assert conn.halted
    assert conn.status == 401
    assert conn.resp_body =~ "authentication_required"
  end

  test "require_user/2 passes through when current_user is set" do
    user = make_user!()

    conn =
      build_conn()
      |> Plug.Test.init_test_session(%{})
      |> UserAuth.put_user_session(user)
      |> UserAuth.call([])
      |> UserAuth.require_user([])

    refute conn.halted
  end
end
