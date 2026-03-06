defmodule HydraXWeb.JobsLiveTest do
  use HydraXWeb.ConnCase

  alias HydraX.Runtime

  test "jobs page can create and run a prompt job", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/jobs")

    view
    |> form("#job-form", %{
      scheduled_job: %{
        name: "Operator sweep",
        kind: "prompt",
        interval_minutes: 30,
        prompt: "Summarize the workspace state.",
        enabled: true
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

    html = render(view)
    assert html =~ "Job executed"
    assert html =~ "success"
  end
end
