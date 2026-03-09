defmodule HydraXWeb.WebchatLiveTest do
  use HydraXWeb.ConnCase

  alias HydraX.Runtime

  test "public webchat opens a conversation and renders replies", %{conn: conn} do
    agent = Runtime.ensure_default_agent!()
    {:ok, _pid} = HydraX.Agent.ensure_started(agent)

    {:ok, _webchat} =
      Runtime.save_webchat_config(%{
        title: "Hydra-X Browser",
        subtitle: "Public runtime ingress",
        welcome_prompt: "Welcome to Hydra-X Webchat.",
        composer_placeholder: "Ask Hydra-X",
        enabled: true,
        default_agent_id: agent.id
      })

    {:ok, view, html} = live(conn, ~p"/webchat")

    assert html =~ "Hydra-X Browser"
    assert html =~ "Welcome to Hydra-X Webchat."

    view
    |> form("form[phx-submit=\"send_message\"]", %{
      "message" => %{"message" => "Webchat should persist and respond."}
    })
    |> render_submit()

    rendered = render(view)
    assert rendered =~ "Webchat should persist and respond."
    assert rendered =~ "Mock response"
  end
end
