defmodule HydraXWeb.ProviderFlowsTest do
  use HydraXWeb.ConnCase

  alias HydraX.Repo
  alias HydraX.Runtime
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
    |> element(~s(button[phx-click="test"][phx-value-id="#{provider.id}"]))
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

  test "providers page can edit and activate a provider", %{conn: conn} do
    {:ok, first} =
      Runtime.save_provider_config(%{
        name: "First Provider",
        kind: "openai_compatible",
        base_url: "https://first.test",
        api_key: "secret",
        model: "gpt-first",
        enabled: false
      })

    {:ok, second} =
      Runtime.save_provider_config(%{
        name: "Second Provider",
        kind: "openai_compatible",
        base_url: "https://second.test",
        api_key: "secret",
        model: "gpt-second",
        enabled: false
      })

    {:ok, view, _html} = live(conn, ~p"/settings/providers")

    view
    |> element(~s(button[phx-click="edit"][phx-value-id="#{first.id}"]))
    |> render_click()

    view
    |> form("form", %{
      "provider_config" => %{
        "name" => "First Provider Updated",
        "kind" => "openai_compatible",
        "base_url" => "https://first.test",
        "api_key" => "secret",
        "model" => "gpt-updated",
        "enabled" => "false"
      }
    })
    |> render_submit()

    assert Runtime.get_provider_config!(first.id).name == "First Provider Updated"

    view
    |> element(~s(button[phx-click="activate"][phx-value-id="#{second.id}"]))
    |> render_click()

    html = render(view)
    assert html =~ "Active provider updated"
    assert Runtime.enabled_provider().id == second.id
  end
end
