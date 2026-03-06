defmodule HydraXWeb.ProviderFlowsTest do
  use HydraXWeb.ConnCase

  alias HydraX.Repo
  alias HydraX.Runtime.ProviderConfig

  setup do
    previous = Application.get_env(:hydra_x, :provider_test_request_fn)

    Application.put_env(:hydra_x, :provider_test_request_fn, fn _opts ->
      {:ok, %{status: 200, body: %{"choices" => [%{"message" => %{"content" => "OK"}}]}}}
    end)

    on_exit(fn ->
      if previous do
        Application.put_env(:hydra_x, :provider_test_request_fn, previous)
      else
        Application.delete_env(:hydra_x, :provider_test_request_fn)
      end
    end)

    :ok
  end

  test "providers page can test a saved provider", %{conn: conn} do
    provider =
      %ProviderConfig{}
      |> ProviderConfig.changeset(%{
        name: "OpenAI Test",
        kind: "openai_compatible",
        base_url: "https://example.test",
        api_key: "secret",
        model: "gpt-test",
        enabled: true
      })
      |> Repo.insert!()

    {:ok, view, _html} = live(conn, ~p"/settings/providers")

    view
    |> element(~s(button[phx-value-id="#{provider.id}"]))
    |> render_click()

    html = render(view)
    assert html =~ "Provider test succeeded"
    assert html =~ "Test reply:"
    assert html =~ "OK"
  end

  test "setup page can test the currently saved provider", %{conn: conn} do
    %ProviderConfig{}
    |> ProviderConfig.changeset(%{
      name: "OpenAI Test",
      kind: "openai_compatible",
      base_url: "https://example.test",
      api_key: "secret",
      model: "gpt-test",
      enabled: true
    })
    |> Repo.insert!()

    {:ok, view, _html} = live(conn, ~p"/setup")

    view
    |> element(~s(button[phx-click="test_provider"]))
    |> render_click()

    html = render(view)
    assert html =~ "Provider test succeeded"
    assert html =~ "Test reply:"
    assert html =~ "OK"
  end
end
