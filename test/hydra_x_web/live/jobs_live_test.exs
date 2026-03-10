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

  test "jobs page can edit and filter jobs", %{conn: conn} do
    agent = Runtime.ensure_default_agent!()

    {:ok, first} =
      Runtime.save_scheduled_job(%{
        agent_id: agent.id,
        name: "Alpha Prompt Job",
        kind: "prompt",
        interval_minutes: 30,
        enabled: true
      })

    {:ok, _second} =
      Runtime.save_scheduled_job(%{
        agent_id: agent.id,
        name: "Beta Backup Job",
        kind: "backup",
        interval_minutes: 240,
        enabled: false
      })

    {:ok, view, _html} = live(conn, ~p"/jobs")

    view
    |> element(~s(button[phx-click="edit"][phx-value-id="#{first.id}"]))
    |> render_click()

    view
    |> form("#job-form", %{
      scheduled_job: %{
        name: "Alpha Prompt Job Updated",
        kind: "prompt",
        interval_minutes: 45,
        prompt: "Updated prompt",
        enabled: true,
        delivery_enabled: false,
        delivery_channel: "telegram",
        delivery_target: ""
      }
    })
    |> render_submit()

    assert Runtime.get_scheduled_job!(first.id).name == "Alpha Prompt Job Updated"

    view
    |> form("form[phx-submit=\"filter_jobs\"]", %{
      "filters" => %{"search" => "Alpha", "kind" => "prompt", "enabled" => "true"}
    })
    |> render_submit()

    html = render(view)
    assert html =~ "Alpha Prompt Job Updated"
    refute html =~ "Beta Backup Job"
  end

  test "jobs page can create a weekly scheduled job", %{conn: conn} do
    _agent = Runtime.ensure_default_agent!()

    {:ok, view, _html} = live(conn, ~p"/jobs")

    view
    |> form("#job-form", %{
      scheduled_job: %{
        name: "Weekly Planning Review",
        kind: "prompt",
        schedule_mode: "weekly",
        interval_minutes: "",
        weekday_csv: "mon,fri",
        run_hour: 8,
        run_minute: 15,
        prompt: "Review weekly plan.",
        enabled: true,
        delivery_enabled: false,
        delivery_channel: "telegram",
        delivery_target: ""
      }
    })
    |> render_submit()

    [job | _] =
      Runtime.list_scheduled_jobs(limit: 10)
      |> Enum.filter(&(&1.name == "Weekly Planning Review"))

    assert job.schedule_mode == "weekly"
    assert job.weekday_csv == "mon,fri"
    assert job.run_hour == 8
    assert job.run_minute == 15

    html = render(view)
    assert html =~ "Weekly Planning Review"
    assert html =~ "weekly mon,fri 08:15"
  end

  test "jobs page can create a job from natural schedule text", %{conn: conn} do
    Runtime.ensure_default_agent!()

    {:ok, view, _html} = live(conn, ~p"/jobs")

    view
    |> form("#job-form", %{
      scheduled_job: %{
        name: "Natural Schedule Job",
        kind: "prompt",
        schedule_text: "daily 09:30",
        interval_minutes: "",
        prompt: "Natural schedule",
        enabled: true,
        delivery_enabled: false,
        delivery_channel: "telegram",
        delivery_target: ""
      }
    })
    |> render_submit()

    [job | _] =
      Runtime.list_scheduled_jobs(limit: 10)
      |> Enum.filter(&(&1.name == "Natural Schedule Job"))

    assert job.schedule_mode == "daily"
    assert job.run_hour == 9
    assert job.run_minute == 30

    html = render(view)
    assert html =~ "Natural Schedule Job"
    assert html =~ "daily 09:30"
  end

  test "jobs page can create and run an ingest scheduled job", %{conn: conn} do
    agent = Runtime.ensure_default_agent!()
    ingest_dir = Path.join(agent.workspace_root, "ingest")
    File.mkdir_p!(ingest_dir)
    File.write!(Path.join(ingest_dir, "scheduled.md"), "# Scheduled\n\nJobs page ingest works.")

    {:ok, view, _html} = live(conn, ~p"/jobs")

    view
    |> form("#job-form", %{
      scheduled_job: %{
        name: "Ingest queue sweep",
        kind: "ingest",
        interval_minutes: 30,
        enabled: true,
        delivery_enabled: false,
        delivery_channel: "telegram",
        delivery_target: ""
      }
    })
    |> render_submit()

    [job | _] =
      Runtime.list_scheduled_jobs(limit: 10)
      |> Enum.filter(&(&1.name == "Ingest queue sweep"))

    view
    |> element(~s(button[phx-click="trigger"][phx-value-id="#{job.id}"]))
    |> render_click()

    [run | _] =
      Runtime.list_job_runs(limit: 5, kind: "ingest", search: "Ingest queue sweep")

    assert run.status == "success"
    assert run.output =~ "scheduled.md"

    html = render(view)
    assert html =~ "Ingest queue sweep"
    assert html =~ "Job executed"
    assert html =~ "success"
  end

  test "jobs page shows scheduler resilience controls and can reset circuits", %{conn: conn} do
    agent = Runtime.ensure_default_agent!()

    {:ok, job} =
      Runtime.save_scheduled_job(%{
        agent_id: agent.id,
        name: "Circuit Breaker Job",
        kind: "prompt",
        interval_minutes: 15,
        enabled: true,
        timeout_seconds: 45,
        retry_limit: 2,
        retry_backoff_seconds: 5,
        pause_after_failures: 3,
        cooldown_minutes: 30,
        run_retention_days: 14,
        active_hour_start: 8,
        active_hour_end: 18,
        circuit_state: "open",
        consecutive_failures: 3,
        last_failure_reason: "provider offline"
      })

    {:ok, view, _html} = live(conn, ~p"/jobs")

    html = render(view)
    assert html =~ "Circuit Breaker Job"
    assert html =~ "circuit open"
    assert html =~ "timeout 45s"
    assert html =~ "active 08:00-18:00 UTC"
    assert html =~ "retention 14 days"

    view
    |> element(~s(button[phx-click="reset_circuit"][phx-value-id="#{job.id}"]))
    |> render_click()

    refreshed = Runtime.get_scheduled_job!(job.id)
    assert refreshed.circuit_state == "closed"

    html = render(view)
    assert html =~ "Scheduler circuit reset"
  end

  test "jobs page saves run retention policy on create", %{conn: conn} do
    Runtime.ensure_default_agent!()

    {:ok, view, _html} = live(conn, ~p"/jobs")

    view
    |> form("#job-form", %{
      scheduled_job: %{
        name: "Retention Job",
        kind: "prompt",
        interval_minutes: 30,
        prompt: "Retention test.",
        enabled: true,
        run_retention_days: 7,
        delivery_enabled: false,
        delivery_channel: "telegram",
        delivery_target: ""
      }
    })
    |> render_submit()

    [job | _] =
      Runtime.list_scheduled_jobs(limit: 10)
      |> Enum.filter(&(&1.name == "Retention Job"))

    assert job.run_retention_days == 7

    html = render(view)
    assert html =~ "Retention Job"
    assert html =~ "retention 7 days"
  end

  test "jobs page can filter and export the run ledger", %{conn: conn} do
    agent = Runtime.ensure_default_agent!()

    {:ok, success_job} =
      Runtime.save_scheduled_job(%{
        agent_id: agent.id,
        name: "Ledger Success Job",
        kind: "backup",
        interval_minutes: 10,
        enabled: true
      })

    {:ok, skipped_job} =
      Runtime.save_scheduled_job(%{
        agent_id: agent.id,
        name: "Ledger Skipped Job",
        kind: "backup",
        interval_minutes: 10,
        enabled: true,
        active_hour_start: rem(DateTime.utc_now().hour + 1, 24),
        active_hour_end: rem(DateTime.utc_now().hour + 2, 24)
      })

    assert {:ok, _run} = Runtime.run_scheduled_job(success_job)
    assert {:ok, _run} = Runtime.run_scheduled_job(skipped_job)

    {:ok, view, _html} = live(conn, ~p"/jobs")

    view
    |> form("form[phx-submit=\"filter_runs\"]", %{
      "run_filters" => %{
        "status" => "skipped",
        "kind" => "backup",
        "delivery_status" => "",
        "search" => "Ledger"
      }
    })
    |> render_submit()

    html = render(view)
    assert html =~ "Ledger Skipped Job"
    assert html =~ "outside_active_hours"

    view
    |> element(~s(button[phx-click="export_runs"]))
    |> render_click()

    html = render(view)
    assert html =~ "Job run ledger exported"
    assert html =~ "Markdown:"
    assert html =~ "JSON:"
  end

  test "jobs page can delete jobs", %{conn: conn} do
    agent = Runtime.ensure_default_agent!()

    {:ok, job} =
      Runtime.save_scheduled_job(%{
        agent_id: agent.id,
        name: "Delete Me Job",
        kind: "prompt",
        interval_minutes: 10,
        enabled: true
      })

    {:ok, view, _html} = live(conn, ~p"/jobs")

    view
    |> element(~s(button[phx-click="delete"][phx-value-id="#{job.id}"]))
    |> render_click()

    html = render(view)
    assert html =~ "Job deleted"
    refute html =~ "Delete Me Job"
    assert_raise Ecto.NoResultsError, fn -> Runtime.get_scheduled_job!(job.id) end
  end
end
