defmodule HydraXWeb.JobsLiveTest do
  use HydraXWeb.ConnCase

  alias HydraX.Runtime

  setup do
    test_pid = self()
    previous = Application.get_env(:hydra_x, :telegram_deliver)

    Application.put_env(:hydra_x, :telegram_deliver, fn payload ->
      send(test_pid, {:job_delivery, payload})
      {:ok, %{provider_message_id: 555}}
    end)

    on_exit(fn ->
      if previous do
        Application.put_env(:hydra_x, :telegram_deliver, previous)
      else
        Application.delete_env(:hydra_x, :telegram_deliver)
      end
    end)

    :ok
  end

  test "jobs page can create and run a prompt job", %{conn: conn} do
    agent = Runtime.ensure_default_agent!()

    {:ok, _telegram} =
      Runtime.save_telegram_config(%{
        bot_token: "test-token",
        bot_username: "hydrax_bot",
        enabled: true,
        default_agent_id: agent.id
      })

    {:ok, view, _html} = live(conn, ~p"/jobs")

    view
    |> form("#job-form", %{
      scheduled_job: %{
        name: "Operator sweep",
        kind: "prompt",
        interval_minutes: 30,
        prompt: "Summarize the workspace state.",
        enabled: true,
        delivery_enabled: true,
        delivery_channel: "telegram",
        delivery_target: "4242"
      }
    })
    |> render_submit()

    html = render(view)
    assert html =~ "Scheduled job saved"
    assert html =~ "Operator sweep"

    [job | _] =
      Runtime.list_scheduled_jobs(limit: 10)
      |> Enum.filter(&(&1.name == "Operator sweep"))

    view
    |> element(~s(button[phx-click="trigger"][phx-value-id="#{job.id}"]))
    |> render_click()

    assert_receive {:job_delivery, %{external_ref: "4242", content: content}}
    assert content =~ "finished with success"

    html = render(view)
    assert html =~ "Job executed"
    assert html =~ "success"
    assert html =~ "delivery delivered via telegram -&gt; 4242"
  end
end
