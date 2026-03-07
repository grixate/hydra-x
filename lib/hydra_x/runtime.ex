defmodule HydraX.Runtime do
  @moduledoc """
  Persistence and orchestration helpers for agents, conversations, providers, and checkpoints.
  """

  import Ecto.Query

  alias HydraX.Config
  alias HydraX.Memory
  alias HydraX.Repo
  alias HydraX.Workspace

  alias HydraX.Runtime.{
    AgentProfile,
    Checkpoint,
    Conversation,
    JobRun,
    OperatorSecret,
    ProviderConfig,
    ScheduledJob,
    TelegramConfig,
    ToolPolicy,
    Turn
  }

  alias HydraX.Gateway.Adapters.Telegram
  alias HydraX.Telemetry

  @default_agent_slug "hydra-primary"

  def list_agents do
    AgentProfile
    |> order_by([agent], desc: agent.is_default, asc: agent.name)
    |> Repo.all()
  end

  def get_agent!(id), do: Repo.get!(AgentProfile, id)

  def get_agent_by_slug(slug) do
    Repo.get_by(AgentProfile, slug: slug)
  end

  def get_default_agent do
    Repo.one(from agent in AgentProfile, where: agent.is_default == true, limit: 1)
  end

  def ensure_default_agent! do
    case get_default_agent() || get_agent_by_slug(@default_agent_slug) do
      nil ->
        attrs = %{
          name: "Hydra Prime",
          slug: @default_agent_slug,
          status: "active",
          description: "Default Hydra-X operator agent",
          is_default: true,
          workspace_root: Config.default_workspace(@default_agent_slug)
        }

        case save_agent(attrs) do
          {:ok, agent} ->
            HydraX.Workspace.Scaffold.copy_template!(agent.workspace_root)
            agent

          {:error, _changeset} ->
            get_agent_by_slug(@default_agent_slug)
        end

      agent ->
        HydraX.Workspace.Scaffold.copy_template!(agent.workspace_root)
        agent
    end
  end

  def change_agent(agent \\ %AgentProfile{}, attrs \\ %{}) do
    AgentProfile.changeset(agent, attrs)
  end

  def save_agent(attrs) when is_map(attrs) do
    save_agent(%AgentProfile{}, attrs)
  end

  def save_agent(%AgentProfile{} = agent, attrs) do
    Repo.transaction(fn ->
      attrs = normalize_agent_attrs(attrs)
      changeset = AgentProfile.changeset(agent, attrs)

      record =
        case Repo.insert_or_update(changeset) do
          {:ok, record} -> record
          {:error, changeset} -> Repo.rollback(changeset)
        end

      if record.is_default do
        from(other in AgentProfile, where: other.id != ^record.id and other.is_default == true)
        |> Repo.update_all(set: [is_default: false])
      end

      HydraX.Workspace.Scaffold.copy_template!(record.workspace_root)
      record
    end)
    |> unwrap_transaction()
  end

  def update_agent_runtime_state(%AgentProfile{} = agent, attrs) when is_map(attrs) do
    current = agent.runtime_state || %{}
    save_agent(agent, %{runtime_state: Map.merge(current, attrs)})
  end

  def toggle_agent_status!(id) do
    agent = get_agent!(id)
    next = if agent.status == "active", do: "paused", else: "active"
    {:ok, updated} = save_agent(agent, %{status: next})

    case updated.status do
      "active" -> start_agent_runtime!(updated.id)
      _ -> stop_agent_runtime!(updated.id)
    end

    updated
  end

  def set_default_agent!(id) do
    agent = get_agent!(id)
    {:ok, updated} = save_agent(agent, %{is_default: true})
    updated
  end

  def repair_agent_workspace!(id) do
    agent = get_agent!(id)
    Workspace.Scaffold.copy_template!(agent.workspace_root)
    agent
  end

  def agent_bulletin(id) when is_integer(id) do
    agent = get_agent!(id)
    bulletin = get_in(agent.runtime_state, ["bulletin"])

    %{
      agent: agent,
      content: bulletin,
      updated_at: get_in(agent.runtime_state, ["bulletin_updated_at"]),
      memory_count:
        Memory.list_memories(agent_id: agent.id, limit: 6, status: "active") |> length()
    }
  end

  def compaction_policy(id) when is_integer(id) do
    agent = get_agent!(id)
    persisted = get_in(agent.runtime_state || %{}, ["compaction_policy"]) || %{}
    defaults = Config.compaction_thresholds()

    %{
      soft: map_integer(persisted["soft"], defaults.soft),
      medium: map_integer(persisted["medium"], defaults.medium),
      hard: map_integer(persisted["hard"], defaults.hard)
    }
  end

  def save_compaction_policy!(id, attrs) when is_integer(id) and is_map(attrs) do
    agent = get_agent!(id)
    policy = normalize_compaction_policy(attrs)
    validate_compaction_policy!(policy)

    {:ok, updated} =
      update_agent_runtime_state(agent, %{
        "compaction_policy" => %{
          "soft" => policy.soft,
          "medium" => policy.medium,
          "hard" => policy.hard
        }
      })

    audit_operator_action("Updated compaction policy for #{updated.slug}",
      agent: updated,
      metadata: %{
        "soft" => policy.soft,
        "medium" => policy.medium,
        "hard" => policy.hard
      }
    )

    policy
  end

  def refresh_agent_bulletin!(id) when is_integer(id) do
    agent = get_agent!(id)
    bulletin = render_agent_bulletin(agent.id)
    updated_at = DateTime.utc_now()

    {:ok, updated_agent} =
      update_agent_runtime_state(agent, %{
        "bulletin" => bulletin,
        "bulletin_updated_at" => updated_at
      })

    audit_operator_action(
      "Refreshed bulletin for #{updated_agent.slug}",
      agent: updated_agent,
      metadata: %{
        "memory_count" => Memory.list_memories(agent_id: agent.id, limit: 6) |> length()
      }
    )

    %{
      agent: updated_agent,
      content: bulletin,
      updated_at: updated_at,
      memory_count:
        Memory.list_memories(agent_id: agent.id, limit: 6, status: "active") |> length()
    }
  end

  def agent_runtime_status(%AgentProfile{} = agent) do
    pid = HydraX.Agent.pid(agent.id)

    %{
      running: not is_nil(pid),
      pid: pid && inspect(pid),
      last_started_at: agent.last_started_at,
      persisted_status: agent.status
    }
  end

  def agent_runtime_status(id), do: get_agent!(id) |> agent_runtime_status()

  def start_agent_runtime!(id) do
    agent = get_agent!(id)
    {:ok, _pid} = HydraX.Agent.ensure_started(agent)

    {:ok, updated} =
      save_agent(agent, %{
        last_started_at: DateTime.utc_now(),
        runtime_state: Map.merge(agent.runtime_state || %{}, %{"running" => true})
      })

    updated
  end

  def stop_agent_runtime!(id) do
    agent = get_agent!(id)
    :ok = HydraX.Agent.ensure_stopped(agent)

    {:ok, updated} =
      save_agent(agent, %{
        runtime_state:
          Map.merge(agent.runtime_state || %{}, %{
            "running" => false,
            "last_stopped_at" => DateTime.utc_now()
          })
      })

    updated
  end

  def restart_agent_runtime!(id) do
    agent = get_agent!(id)
    :ok = HydraX.Agent.ensure_stopped(agent)
    start_agent_runtime!(agent.id)
  end

  def reconcile_agents! do
    ensure_default_agent!()

    list_agents()
    |> Enum.reduce(%{started: 0, stopped: 0}, fn agent, acc ->
      case {agent.status, HydraX.Agent.running?(agent)} do
        {"active", false} ->
          start_agent_runtime!(agent.id)
          %{acc | started: acc.started + 1}

        {"active", true} ->
          acc

        {_, true} ->
          stop_agent_runtime!(agent.id)
          %{acc | stopped: acc.stopped + 1}

        _ ->
          acc
      end
    end)
  end

  def list_provider_configs do
    ProviderConfig
    |> order_by([provider], desc: provider.enabled, asc: provider.name)
    |> Repo.all()
  end

  def get_provider_config!(id), do: Repo.get!(ProviderConfig, id)

  def enabled_provider do
    Repo.one(from provider in ProviderConfig, where: provider.enabled == true, limit: 1)
  end

  def change_provider_config(provider \\ %ProviderConfig{}, attrs \\ %{}) do
    ProviderConfig.changeset(provider, attrs)
  end

  def save_provider_config(attrs) when is_map(attrs) do
    save_provider_config(%ProviderConfig{}, attrs)
  end

  def save_provider_config(%ProviderConfig{} = provider, attrs) do
    Repo.transaction(fn ->
      changeset = ProviderConfig.changeset(provider, attrs)

      record =
        case Repo.insert_or_update(changeset) do
          {:ok, record} -> record
          {:error, changeset} -> Repo.rollback(changeset)
        end

      if record.enabled do
        from(other in ProviderConfig, where: other.id != ^record.id and other.enabled == true)
        |> Repo.update_all(set: [enabled: false])
      end

      record
    end)
    |> unwrap_transaction()
  end

  def activate_provider!(id) do
    provider = get_provider_config!(id)
    {:ok, updated} = save_provider_config(provider, %{enabled: true})
    updated
  end

  def toggle_provider_enabled!(id) do
    provider = get_provider_config!(id)
    {:ok, updated} = save_provider_config(provider, %{enabled: !provider.enabled})
    updated
  end

  def delete_provider_config!(id) do
    provider = get_provider_config!(id)
    Repo.delete!(provider)
  end

  def get_tool_policy do
    Repo.get_by(ToolPolicy, scope: "default")
  end

  def ensure_tool_policy! do
    case get_tool_policy() do
      nil ->
        {:ok, policy} =
          save_tool_policy(%{
            scope: "default",
            workspace_read_enabled: true,
            http_fetch_enabled: true,
            shell_command_enabled: true
          })

        policy

      policy ->
        policy
    end
  end

  def change_tool_policy(policy \\ nil, attrs \\ %{}) do
    (policy || get_tool_policy() || %ToolPolicy{scope: "default"})
    |> ToolPolicy.changeset(attrs)
  end

  def save_tool_policy(attrs) when is_map(attrs) do
    save_tool_policy(get_tool_policy() || %ToolPolicy{}, attrs)
  end

  def save_tool_policy(%ToolPolicy{} = policy, attrs) do
    policy
    |> ToolPolicy.changeset(normalize_string_keys(attrs) |> Map.put_new("scope", "default"))
    |> Repo.insert_or_update()
  end

  def effective_tool_policy do
    policy = get_tool_policy() || %ToolPolicy{}

    %{
      workspace_read_enabled: Map.get(policy, :workspace_read_enabled, true),
      http_fetch_enabled: Map.get(policy, :http_fetch_enabled, true),
      shell_command_enabled: Map.get(policy, :shell_command_enabled, true),
      shell_allowlist: csv_values(policy.shell_allowlist_csv, Config.shell_allowlist()),
      http_allowlist: csv_values(policy.http_allowlist_csv, Config.http_allowlist())
    }
  end

  def list_scheduled_jobs(opts \\ []) do
    agent_id = Keyword.get(opts, :agent_id)
    kind = Keyword.get(opts, :kind)
    enabled = Keyword.get(opts, :enabled)
    search = Keyword.get(opts, :search)
    limit = Keyword.get(opts, :limit, 50)

    ScheduledJob
    |> preload([:agent])
    |> maybe_filter_scheduled_job_agent(agent_id)
    |> maybe_filter_scheduled_job_kind(kind)
    |> maybe_filter_scheduled_job_enabled(enabled)
    |> maybe_filter_scheduled_job_search(search)
    |> order_by([job], asc: job.next_run_at, asc: job.name)
    |> limit(^limit)
    |> Repo.all()
  end

  def get_scheduled_job!(id) do
    ScheduledJob
    |> Repo.get!(id)
    |> Repo.preload([:agent])
  end

  def change_scheduled_job(job \\ %ScheduledJob{}, attrs \\ %{}) do
    ScheduledJob.changeset(job, attrs)
  end

  def save_scheduled_job(attrs) when is_map(attrs), do: save_scheduled_job(%ScheduledJob{}, attrs)

  def save_scheduled_job(%ScheduledJob{} = job, attrs) do
    normalized_attrs = normalize_string_keys(attrs)

    interval_minutes =
      persisted_integer(normalized_attrs, "interval_minutes", job.interval_minutes || 60)

    run_hour = persisted_integer(normalized_attrs, "run_hour", job.run_hour)
    run_minute = persisted_integer(normalized_attrs, "run_minute", job.run_minute)
    schedule_mode = Map.get(normalized_attrs, "schedule_mode", job.schedule_mode || "interval")
    weekday_csv = persisted_weekday_csv(normalized_attrs, "weekday_csv", job.weekday_csv)

    interval_minutes = interval_minutes || job.interval_minutes || 60

    next_run_at =
      case blank_to_nil(Map.get(normalized_attrs, "next_run_at")) do
        nil ->
          next_run_at(%ScheduledJob{
            job
            | schedule_mode: schedule_mode,
              interval_minutes: interval_minutes || job.interval_minutes,
              weekday_csv: weekday_csv,
              run_hour: run_hour || job.run_hour,
              run_minute: run_minute || job.run_minute
          })

        value ->
          value
      end

    attrs =
      normalized_attrs
      |> Map.put("schedule_mode", schedule_mode)
      |> Map.put("interval_minutes", interval_minutes)
      |> Map.put("weekday_csv", weekday_csv)
      |> Map.put("run_hour", run_hour)
      |> Map.put("run_minute", run_minute)
      |> Map.put("next_run_at", next_run_at)

    job
    |> ScheduledJob.changeset(attrs)
    |> Repo.insert_or_update()
  end

  def delete_scheduled_job!(id) do
    job = get_scheduled_job!(id)
    Repo.delete!(job)
  end

  def list_due_scheduled_jobs(now) do
    ScheduledJob
    |> where(
      [job],
      job.enabled == true and not is_nil(job.next_run_at) and job.next_run_at <= ^now
    )
    |> preload([:agent])
    |> Repo.all()
  end

  def recent_job_runs(limit \\ 20) do
    JobRun
    |> order_by([run], desc: run.inserted_at)
    |> limit(^limit)
    |> preload([:scheduled_job, :agent])
    |> Repo.all()
  end

  def list_job_runs(job_id, limit \\ 20) do
    JobRun
    |> where([run], run.scheduled_job_id == ^job_id)
    |> order_by([run], desc: run.inserted_at)
    |> limit(^limit)
    |> preload([:scheduled_job, :agent])
    |> Repo.all()
  end

  def ensure_heartbeat_job!(agent_id) do
    ensure_named_job!(agent_id, "heartbeat", "Workspace heartbeat", %{
      interval_minutes: 60,
      enabled: true
    })
  end

  def ensure_backup_job!(agent_id) do
    ensure_named_job!(agent_id, "backup", "Portable backup bundle", %{
      interval_minutes: 1_440,
      enabled: true
    })
  end

  def ensure_default_jobs! do
    case get_default_agent() do
      nil ->
        []

      agent ->
        [
          ensure_heartbeat_job!(agent.id),
          ensure_backup_job!(agent.id)
        ]
    end
  end

  def run_scheduled_job(%ScheduledJob{} = job) do
    started_at = DateTime.utc_now()

    {:ok, %{job: job, run: run}} =
      Ecto.Multi.new()
      |> Ecto.Multi.update(
        :job,
        ScheduledJob.changeset(job, %{
          last_run_at: started_at,
          next_run_at: next_run_at(job, started_at)
        })
      )
      |> Ecto.Multi.insert(
        :run,
        JobRun.changeset(%JobRun{}, %{
          scheduled_job_id: job.id,
          agent_id: job.agent_id,
          status: "running",
          started_at: started_at
        })
      )
      |> Repo.transaction()

    case execute_scheduled_job(job) do
      {:ok, output, metadata} ->
        Telemetry.scheduler_job(job.kind, :ok)

        {:ok, run} =
          run
          |> JobRun.changeset(%{
            status: "success",
            finished_at: DateTime.utc_now(),
            output: output,
            metadata: metadata
          })
          |> Repo.update()

        maybe_deliver_job_run(job, run)

      {:error, reason} ->
        Telemetry.scheduler_job(job.kind, :error, %{reason: inspect(reason)})

        {:ok, run} =
          run
          |> JobRun.changeset(%{
            status: "error",
            finished_at: DateTime.utc_now(),
            output: inspect(reason),
            metadata: %{"error" => inspect(reason)}
          })
          |> Repo.update()

        maybe_deliver_job_run(job, run)
    end
  end

  defp maybe_deliver_job_run(%ScheduledJob{delivery_enabled: false}, run), do: {:ok, run}
  defp maybe_deliver_job_run(%ScheduledJob{delivery_enabled: nil}, run), do: {:ok, run}

  defp maybe_deliver_job_run(%ScheduledJob{} = job, %JobRun{} = run) do
    case deliver_job_run(job, run) do
      {:ok, delivery} ->
        update_job_run_delivery(run, delivery)

      {:error, reason} ->
        HydraX.Safety.log_event(%{
          agent_id: job.agent_id,
          category: "scheduler",
          level: "error",
          message: "Scheduled job delivery failed",
          metadata: %{
            job_id: job.id,
            job_name: job.name,
            reason: inspect(reason),
            channel: job.delivery_channel,
            target: job.delivery_target
          }
        })

        update_job_run_delivery(run, %{
          "status" => "failed",
          "channel" => job.delivery_channel,
          "target" => job.delivery_target,
          "attempted_at" => DateTime.utc_now(),
          "reason" => inspect(reason)
        })
    end
  end

  defp deliver_job_run(%ScheduledJob{delivery_channel: "telegram", delivery_target: target}, run) do
    with config when not is_nil(config) <- enabled_telegram_config(),
         true <- is_binary(target) and target != "",
         {:ok, state} <-
           Telegram.connect(%{
             "bot_token" => config.bot_token,
             "bot_username" => config.bot_username,
             "webhook_secret" => config.webhook_secret,
             "deliver" => Application.get_env(:hydra_x, :telegram_deliver)
           }),
         {:ok, metadata} <-
           normalize_delivery_result(
             Telegram.send_response(
               %{content: job_delivery_message(run), external_ref: target},
               state
             )
           ) do
      {:ok,
       %{
         "status" => "delivered",
         "channel" => "telegram",
         "target" => target,
         "delivered_at" => DateTime.utc_now(),
         "metadata" => stringify_metadata(metadata)
       }}
    else
      nil -> {:error, :telegram_not_configured}
      false -> {:error, :missing_delivery_target}
      {:error, reason} -> {:error, reason}
    end
  end

  defp deliver_job_run(%ScheduledJob{delivery_channel: channel}, _run) do
    {:error, {:unsupported_delivery_channel, channel}}
  end

  defp normalize_delivery_result(:ok), do: {:ok, %{}}
  defp normalize_delivery_result({:ok, metadata}) when is_map(metadata), do: {:ok, metadata}
  defp normalize_delivery_result({:error, reason}), do: {:error, reason}

  defp update_job_run_delivery(run, delivery) do
    metadata =
      (run.metadata || %{})
      |> Map.put("delivery", delivery)

    run
    |> JobRun.changeset(%{metadata: metadata})
    |> Repo.update()
  end

  defp job_delivery_message(run) do
    """
    Hydra-X scheduled job #{run.scheduled_job_id} finished with #{run.status}.

    #{run.output || "No output captured."}
    """
    |> String.trim()
  end

  defp stringify_metadata(map) do
    Enum.reduce(map, %{}, fn
      {key, value}, acc when is_atom(key) -> Map.put(acc, Atom.to_string(key), value)
      {key, value}, acc -> Map.put(acc, key, value)
    end)
  end

  def test_provider_config(%ProviderConfig{} = provider, opts \\ []) do
    request =
      %{
        provider_config: provider,
        messages: [
          %{role: "system", content: "You are a terse provider connectivity probe."},
          %{role: "user", content: "Reply with OK if you can read this request."}
        ],
        tool_results: [],
        bulletin: nil,
        request_options:
          Keyword.get(opts, :request_options, receive_timeout: 10_000, retry: false)
      }
      |> maybe_put_request_fn_from_config()
      |> maybe_put_request_fn(opts)

    provider
    |> provider_module()
    |> apply(:complete, [request])
  end

  def enabled_telegram_config do
    TelegramConfig
    |> where([config], config.enabled == true)
    |> preload([:default_agent])
    |> limit(1)
    |> Repo.one()
  end

  def list_telegram_configs do
    TelegramConfig
    |> preload([:default_agent])
    |> order_by([config], desc: config.enabled, desc: config.updated_at)
    |> Repo.all()
  end

  def change_telegram_config(config \\ %TelegramConfig{}, attrs \\ %{}) do
    TelegramConfig.changeset(config, attrs)
  end

  def save_telegram_config(attrs) when is_map(attrs) do
    config = enabled_telegram_config() || List.first(list_telegram_configs()) || %TelegramConfig{}
    save_telegram_config(config, attrs)
  end

  def save_telegram_config(%TelegramConfig{} = config, attrs) do
    Repo.transaction(fn ->
      changeset = TelegramConfig.changeset(config, attrs)

      record =
        case Repo.insert_or_update(changeset) do
          {:ok, record} -> record
          {:error, changeset} -> Repo.rollback(changeset)
        end

      if record.enabled do
        from(other in TelegramConfig, where: other.id != ^record.id and other.enabled == true)
        |> Repo.update_all(set: [enabled: false])
      end

      Repo.preload(record, [:default_agent])
    end)
    |> unwrap_transaction()
  end

  def register_telegram_webhook(%TelegramConfig{} = config, opts \\ []) do
    url = Keyword.get(opts, :url, Config.telegram_webhook_url())
    request_fn = Keyword.get(opts, :request_fn, &Telegram.register_webhook/4)

    with true <- config.bot_token not in [nil, ""],
         :ok <- request_fn.(config.bot_token, url, config.webhook_secret, opts),
         {:ok, updated} <-
           save_telegram_config(config, %{
             webhook_url: url,
             webhook_registered_at: DateTime.utc_now(),
             webhook_last_checked_at: DateTime.utc_now(),
             webhook_last_error: nil,
             enabled: true
           }) do
      audit_operator_action(
        "Registered Telegram webhook",
        agent_id: updated.default_agent_id,
        metadata: %{"webhook_url" => updated.webhook_url}
      )

      {:ok, updated}
    else
      false -> {:error, :missing_bot_token}
      {:error, reason} -> {:error, reason}
    end
  end

  def sync_telegram_webhook_info(%TelegramConfig{} = config, opts \\ []) do
    request_fn = Keyword.get(opts, :request_fn, &Telegram.webhook_info/2)

    with true <- config.bot_token not in [nil, ""],
         {:ok, result} <- request_fn.(config.bot_token, opts),
         {:ok, updated} <-
           save_telegram_config(config, %{
             webhook_last_checked_at: DateTime.utc_now(),
             webhook_pending_update_count: result["pending_update_count"] || 0,
             webhook_last_error: blank_to_nil(result["last_error_message"]),
             webhook_url: blank_to_nil(result["url"]) || config.webhook_url
           }) do
      audit_operator_action(
        "Synced Telegram webhook status",
        agent_id: updated.default_agent_id,
        metadata: %{
          "pending_update_count" => updated.webhook_pending_update_count || 0,
          "webhook_url" => updated.webhook_url
        }
      )

      {:ok, updated}
    else
      false ->
        {:error, :missing_bot_token}

      {:error, reason} ->
        save_telegram_config(config, %{
          webhook_last_checked_at: DateTime.utc_now(),
          webhook_last_error: inspect(reason)
        })

        {:error, reason}
    end
  end

  def delete_telegram_webhook(%TelegramConfig{} = config, opts \\ []) do
    request_fn = Keyword.get(opts, :request_fn, &Telegram.delete_webhook/2)

    with true <- config.bot_token not in [nil, ""],
         :ok <- request_fn.(config.bot_token, opts),
         {:ok, updated} <-
           save_telegram_config(config, %{
             enabled: false,
             webhook_registered_at: nil,
             webhook_last_checked_at: DateTime.utc_now(),
             webhook_pending_update_count: 0,
             webhook_last_error: nil
           }) do
      audit_operator_action(
        "Removed Telegram webhook",
        agent_id: updated.default_agent_id,
        metadata: %{"webhook_url" => updated.webhook_url}
      )

      {:ok, updated}
    else
      false -> {:error, :missing_bot_token}
      {:error, reason} -> {:error, reason}
    end
  end

  def test_telegram_delivery(%TelegramConfig{} = config, target, message, opts \\ []) do
    target = blank_to_nil(to_string(target || ""))
    message = blank_to_nil(message)
    deliver = Keyword.get(opts, :deliver, Application.get_env(:hydra_x, :telegram_deliver))

    cond do
      is_nil(target) ->
        {:error, :missing_target}

      is_nil(message) ->
        {:error, :missing_message}

      blank_to_nil(config.bot_token) == nil ->
        {:error, :missing_bot_token}

      true ->
        with {:ok, state} <-
               Telegram.connect(%{
                 "bot_token" => config.bot_token,
                 "bot_username" => config.bot_username,
                 "webhook_secret" => config.webhook_secret,
                 "deliver" => deliver
               }),
             {:ok, metadata} <-
               Telegram.send_response(%{content: message, external_ref: target}, state) do
          audit_operator_action(
            "Sent Telegram smoke test to #{target}",
            agent_id: config.default_agent_id,
            metadata: %{"channel" => "telegram", "target" => target}
          )

          {:ok, %{target: target, message: message, metadata: metadata}}
        end
    end
  end

  def get_operator_secret do
    Repo.get_by(OperatorSecret, scope: "control_plane")
  end

  def operator_password_configured? do
    not is_nil(get_operator_secret())
  end

  def change_operator_secret(secret \\ nil, attrs \\ %{}) do
    (secret || get_operator_secret() || %OperatorSecret{})
    |> OperatorSecret.changeset(attrs)
  end

  def save_operator_secret_password(attrs) when is_map(attrs) do
    attrs =
      attrs
      |> normalize_string_keys()
      |> Map.put_new("scope", "control_plane")

    changeset = OperatorSecret.changeset(%OperatorSecret{}, attrs)

    if changeset.valid? do
      secret = Ecto.Changeset.apply_changes(changeset)

      retry_on_busy(fn ->
        Repo.insert(
          changeset,
          on_conflict: [
            set: [
              password_hash: secret.password_hash,
              password_salt: secret.password_salt,
              last_rotated_at: secret.last_rotated_at,
              updated_at: DateTime.utc_now()
            ]
          ],
          conflict_target: :scope,
          returning: true
        )
      end)
    else
      {:error, changeset}
    end
  end

  def authenticate_operator(password) when is_binary(password) do
    case get_operator_secret() do
      nil ->
        {:error, :not_configured}

      %OperatorSecret{} = secret ->
        if OperatorSecret.verify_password(secret, password) do
          :ok
        else
          {:error, :unauthorized}
        end
    end
  end

  def list_conversations(opts \\ []) do
    agent_id = Keyword.get(opts, :agent_id)
    status = Keyword.get(opts, :status)
    channel = Keyword.get(opts, :channel)
    search = Keyword.get(opts, :search)
    limit = Keyword.get(opts, :limit, 25)

    Conversation
    |> preload([:agent])
    |> maybe_filter_agent(agent_id)
    |> maybe_filter_conversation_status(status)
    |> maybe_filter_conversation_channel(channel)
    |> maybe_filter_conversation_search(search)
    |> order_by([conversation], desc: conversation.updated_at)
    |> limit(^limit)
    |> Repo.all()
  end

  def get_conversation!(id) do
    Conversation
    |> Repo.get!(id)
    |> Repo.preload([:agent, turns: from(turn in Turn, order_by: turn.sequence)])
  end

  def find_conversation(agent_id, channel, external_ref) do
    Repo.get_by(Conversation, agent_id: agent_id, channel: channel, external_ref: external_ref)
  end

  def start_conversation(%AgentProfile{} = agent, attrs \\ %{}) do
    attrs = normalize_string_keys(attrs)

    params = %{
      agent_id: agent.id,
      channel: Map.get(attrs, "channel", "cli"),
      status: Map.get(attrs, "status", "active"),
      title: Map.get(attrs, "title", agent.name),
      external_ref: Map.get(attrs, "external_ref"),
      metadata: Map.get(attrs, "metadata", %{}),
      last_message_at: DateTime.utc_now()
    }

    %Conversation{}
    |> Conversation.changeset(params)
    |> Repo.insert()
  end

  def save_conversation(%Conversation{} = conversation, attrs) do
    conversation
    |> Conversation.changeset(normalize_string_keys(attrs))
    |> Repo.update()
  end

  def archive_conversation!(id) do
    conversation = get_conversation!(id)
    {:ok, updated} = save_conversation(conversation, %{status: "archived"})

    audit_operator_action("Archived conversation #{updated.id}",
      agent_id: updated.agent_id,
      conversation_id: updated.id
    )

    updated
  end

  def conversation_compaction(id) when is_integer(id) do
    conversation = get_conversation!(id)
    checkpoint = get_checkpoint(conversation.id, "compactor")
    state = (checkpoint && checkpoint.state) || %{}
    turns = list_turns(conversation.id)
    thresholds = compaction_policy(conversation.agent_id)

    %{
      conversation: conversation,
      turn_count: length(turns),
      level: state["level"],
      summary: state["summary"],
      updated_at: state["updated_at"],
      checkpoint_id: checkpoint && checkpoint.id,
      thresholds: thresholds
    }
  end

  def review_conversation_compaction!(id) when is_integer(id) do
    conversation = get_conversation!(id)

    {:ok, _pid} =
      HydraX.Agent.ensure_started(conversation.agent || get_agent!(conversation.agent_id))

    compaction = HydraX.Agent.Compactor.review_now(conversation.agent_id, conversation.id)

    audit_operator_action(
      "Reviewed compaction for conversation #{conversation.id}",
      agent_id: conversation.agent_id,
      conversation_id: conversation.id,
      metadata: %{"level" => compaction.level, "turn_count" => compaction.turn_count}
    )

    compaction
  end

  def reset_conversation_compaction!(id) when is_integer(id) do
    conversation = get_conversation!(id)

    from(checkpoint in Checkpoint,
      where:
        checkpoint.conversation_id == ^conversation.id and checkpoint.process_type == "compactor"
    )
    |> Repo.delete_all()

    audit_operator_action(
      "Reset compaction for conversation #{conversation.id}",
      agent_id: conversation.agent_id,
      conversation_id: conversation.id
    )

    conversation_compaction(conversation.id)
  end

  def export_conversation_transcript!(id) do
    conversation = get_conversation!(id)
    agent = conversation.agent || get_agent!(conversation.agent_id)
    path = transcript_path(agent, conversation)

    File.mkdir_p!(Path.dirname(path))
    File.write!(path, render_transcript(conversation))

    audit_operator_action(
      "Exported transcript for conversation #{conversation.id}",
      agent: agent,
      conversation_id: conversation.id,
      metadata: %{"path" => path}
    )

    %{conversation: conversation, agent: agent, path: path}
  end

  def list_turns(conversation_id) do
    Turn
    |> where([turn], turn.conversation_id == ^conversation_id)
    |> order_by([turn], asc: turn.sequence)
    |> Repo.all()
  end

  def append_turn(%Conversation{} = conversation, attrs) do
    sequence =
      Repo.one(
        from turn in Turn,
          where: turn.conversation_id == ^conversation.id,
          select: coalesce(max(turn.sequence), 0)
      ) + 1

    params =
      attrs
      |> normalize_string_keys()
      |> Map.merge(%{
        "conversation_id" => conversation.id,
        "sequence" => sequence,
        "metadata" => Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{}))
      })

    Repo.transaction(fn ->
      turn =
        %Turn{}
        |> Turn.changeset(params)
        |> Repo.insert!()

      conversation
      |> Conversation.changeset(%{last_message_at: DateTime.utc_now()})
      |> Repo.update!()

      turn
    end)
    |> unwrap_transaction()
  end

  def get_checkpoint(conversation_id, process_type) do
    Repo.get_by(Checkpoint, conversation_id: conversation_id, process_type: process_type)
  end

  def upsert_checkpoint(conversation_id, process_type, state) when is_map(state) do
    checkpoint = get_checkpoint(conversation_id, process_type) || %Checkpoint{}

    checkpoint
    |> Checkpoint.changeset(%{
      conversation_id: conversation_id,
      process_type: process_type,
      state: state
    })
    |> Repo.insert_or_update()
  end

  def update_conversation_metadata(%Conversation{} = conversation, attrs) when is_map(attrs) do
    metadata = Map.merge(conversation.metadata || %{}, attrs)

    conversation
    |> Conversation.changeset(%{metadata: metadata})
    |> Repo.update()
  end

  defp render_agent_bulletin(agent_id) do
    Memory.list_memories(agent_id: agent_id, limit: 6, status: "active")
    |> Enum.map_join("\n", fn memory -> "- [#{memory.type}] #{memory.content}" end)
  end

  defp audit_operator_action(message, opts) do
    case resolve_audit_agent(opts) do
      nil ->
        :ok

      agent ->
        HydraX.Safety.log_event(%{
          agent_id: agent.id,
          conversation_id: Keyword.get(opts, :conversation_id),
          category: "operator",
          level: "info",
          message: message,
          metadata: Keyword.get(opts, :metadata, %{})
        })

        :ok
    end
  end

  defp resolve_audit_agent(opts) do
    cond do
      match?(%AgentProfile{}, Keyword.get(opts, :agent)) ->
        Keyword.get(opts, :agent)

      is_integer(Keyword.get(opts, :agent_id)) ->
        Repo.get(AgentProfile, Keyword.get(opts, :agent_id))

      true ->
        get_default_agent() || List.first(list_agents())
    end
  end

  def health_snapshot(opts \\ []) do
    provider = enabled_provider()
    default_agent = get_default_agent()
    budget_policy = default_agent && HydraX.Budget.ensure_policy!(default_agent.id)
    memory_status = memory_triage_status(default_agent)
    safety_counts = HydraX.Safety.recent_counts()
    system = system_status()
    backups = backup_status()
    safety_errors = Map.get(safety_counts, "error", 0)
    safety_warnings = Map.get(safety_counts, "warn", 0)

    checks = [
      %{name: "database", status: :ok, detail: "SQLite repo online"},
      %{
        name: "agents",
        status: if(list_agents() == [], do: :warn, else: :ok),
        detail: "#{length(list_agents())} configured"
      },
      %{
        name: "providers",
        status: if(provider, do: :ok, else: :warn),
        detail: (provider && "#{provider.kind}: #{provider.model}") || "mock fallback"
      },
      %{
        name: "auth",
        status: if(operator_password_configured?(), do: :ok, else: :warn),
        detail:
          case operator_status() do
            %{configured: true, last_rotated_at: rotated_at} when not is_nil(rotated_at) ->
              "operator password set; rotated #{Calendar.strftime(rotated_at, "%Y-%m-%d %H:%M UTC")}"

            %{configured: true} ->
              "operator password set"

            _ ->
              "control plane open until operator password is set"
          end
      },
      %{
        name: "telegram",
        status: if(enabled_telegram_config(), do: :ok, else: :warn),
        detail:
          case enabled_telegram_config() do
            %{bot_username: username, default_agent: %{name: agent_name}}
            when is_binary(username) and username != "" ->
              "@#{username} -> #{agent_name}"

            %{default_agent: %{name: agent_name}} ->
              "configured -> #{agent_name}"

            nil ->
              "not configured"
          end
      },
      %{
        name: "budget",
        status: if(budget_policy, do: :ok, else: :warn),
        detail:
          case budget_policy do
            nil -> "no policy configured"
            policy -> "daily #{policy.daily_limit}; conversation #{policy.conversation_limit}"
          end
      },
      %{
        name: "memory",
        status: if(Map.get(memory_status.counts, "conflicted", 0) > 0, do: :warn, else: :ok),
        detail:
          "active #{Map.get(memory_status.counts, "active", 0)}; conflicted #{Map.get(memory_status.counts, "conflicted", 0)}; superseded #{Map.get(memory_status.counts, "superseded", 0)}"
      },
      %{
        name: "safety",
        status: if(safety_errors > 0 or safety_warnings > 0, do: :warn, else: :ok),
        detail:
          cond do
            safety_errors > 0 ->
              "#{safety_errors} errors; #{safety_warnings} warnings in the last 24h"

            safety_warnings > 0 ->
              "#{safety_warnings} warnings in the last 24h"

            true ->
              "no recent safety events"
          end
      },
      %{
        name: "tools",
        status: :ok,
        detail: tool_detail(tool_status())
      },
      %{
        name: "scheduler",
        status: if(list_scheduled_jobs(limit: 1) == [], do: :warn, else: :ok),
        detail:
          case list_scheduled_jobs(limit: 5) do
            [] -> "no scheduled jobs configured"
            jobs -> "#{length(jobs)} jobs configured"
          end
      },
      %{
        name: "system",
        status: if(system.alarms == [], do: :ok, else: :warn),
        detail:
          case system.alarms do
            [] -> "no active OTP alarms"
            alarms -> Enum.join(alarms, "; ")
          end
      },
      %{
        name: "backups",
        status: if(backups.latest_backup, do: :ok, else: :warn),
        detail:
          case backups.latest_backup do
            nil -> "no backup manifests found in #{backups.root}"
            backup -> "latest backup #{backup["archive_path"]}"
          end
      },
      %{
        name: "workspace",
        status: :ok,
        detail: Config.workspace_root()
      }
    ]

    checks
    |> maybe_filter_check_status(Keyword.get(opts, :status))
    |> maybe_filter_check_search(Keyword.get(opts, :search))
  end

  def telegram_status do
    case enabled_telegram_config() || List.first(list_telegram_configs()) do
      nil ->
        %{
          configured: false,
          enabled: false,
          bot_username: nil,
          webhook_url: Config.telegram_webhook_url(),
          registered_at: nil,
          last_checked_at: nil,
          pending_update_count: 0,
          last_error: nil,
          default_agent_name: nil
        }

      config ->
        %{
          configured: true,
          enabled: config.enabled,
          bot_username: config.bot_username,
          webhook_url: config.webhook_url || Config.telegram_webhook_url(),
          registered_at: config.webhook_registered_at,
          last_checked_at: config.webhook_last_checked_at,
          pending_update_count: config.webhook_pending_update_count || 0,
          last_error: config.webhook_last_error,
          default_agent_name: config.default_agent && config.default_agent.name
        }
    end
  end

  def budget_status(agent_or_id \\ nil)
  def budget_status(%AgentProfile{} = agent), do: do_budget_status(agent)

  def budget_status(agent_id) when is_integer(agent_id),
    do: get_agent!(agent_id) |> do_budget_status()

  def budget_status(nil), do: do_budget_status(get_default_agent())

  defp do_budget_status(agent) do
    policy = agent && HydraX.Budget.ensure_policy!(agent.id)

    if agent && policy do
      usage = HydraX.Budget.usage_snapshot(agent.id, nil)

      %{
        agent_name: agent.name,
        agent_id: agent.id,
        policy: policy,
        usage: usage,
        safety_events: HydraX.Safety.recent_events(agent.id, 10),
        recent_usage: HydraX.Budget.recent_usage(agent.id, 15)
      }
    else
      %{
        agent_name: nil,
        agent_id: nil,
        policy: nil,
        usage: nil,
        safety_events: [],
        recent_usage: []
      }
    end
  end

  def memory_triage_status(agent_or_id \\ nil)
  def memory_triage_status(%AgentProfile{} = agent), do: do_memory_triage_status(agent)

  def memory_triage_status(agent_id) when is_integer(agent_id),
    do: get_agent!(agent_id) |> do_memory_triage_status()

  def memory_triage_status(nil), do: do_memory_triage_status(get_default_agent())

  defp do_memory_triage_status(nil) do
    %{agent_id: nil, agent_name: nil, counts: %{}, recent_conflicts: []}
  end

  defp do_memory_triage_status(agent) do
    %{
      agent_id: agent.id,
      agent_name: agent.name,
      counts: Memory.status_counts(agent_id: agent.id),
      recent_conflicts: Memory.list_memories(agent_id: agent.id, status: "conflicted", limit: 8)
    }
  end

  def safety_status(opts \\ []) do
    counts = HydraX.Safety.recent_counts()
    statuses = HydraX.Safety.status_counts()
    limit = Keyword.get(opts, :limit, 12)
    level = Keyword.get(opts, :level)
    category = Keyword.get(opts, :category)
    status = Keyword.get(opts, :status)

    %{
      counts: %{
        info: Map.get(counts, "info", 0),
        warn: Map.get(counts, "warn", 0),
        error: Map.get(counts, "error", 0)
      },
      statuses: %{
        open: Map.get(statuses, "open", 0),
        acknowledged: Map.get(statuses, "acknowledged", 0),
        resolved: Map.get(statuses, "resolved", 0)
      },
      recent_events:
        HydraX.Safety.list_events(limit: limit, level: level, category: category, status: status),
      categories: HydraX.Safety.categories()
    }
  end

  def operator_status do
    case get_operator_secret() do
      nil ->
        %{configured: false, last_rotated_at: nil}

      secret ->
        %{configured: true, last_rotated_at: secret.last_rotated_at}
    end
  end

  def tool_status do
    policy = effective_tool_policy()

    %{
      workspace_guard: policy.workspace_read_enabled,
      url_guard: policy.http_fetch_enabled,
      shell_command_enabled: policy.shell_command_enabled,
      shell_allowlist: policy.shell_allowlist,
      http_allowlist: policy.http_allowlist
    }
  end

  def scheduler_status do
    %{
      jobs: list_scheduled_jobs(limit: 50),
      runs: recent_job_runs(20)
    }
  end

  def observability_status do
    %{
      telemetry: HydraX.Telemetry.Store.snapshot(),
      scheduler: %{
        total_jobs: length(list_scheduled_jobs(limit: 100)),
        recent_runs: recent_job_runs(10)
      },
      system: system_status(),
      backups: backup_status()
    }
  end

  def system_status do
    alarms =
      :alarm_handler.get_alarms()
      |> Enum.map(&format_alarm/1)

    %{
      alarms: alarms,
      database_path: Config.repo_database_path()
    }
  end

  def readiness_report(opts \\ []) do
    tool_policy = effective_tool_policy()
    backup_root = Config.backup_root()
    telegram = telegram_status()
    backups = backup_status()
    public_url = Config.public_base_url()
    local_url? = local_public_url?(public_url)
    memory_status = memory_triage_status()

    items = [
      %{
        id: "operator_password",
        label: "Operator password configured",
        required: true,
        status: if(operator_password_configured?(), do: :ok, else: :warn),
        detail:
          if(operator_password_configured?(),
            do: "control plane requires login",
            else: "set a password on /setup before exposing the node"
          )
      },
      %{
        id: "public_url",
        label: "Public URL points beyond localhost",
        required: true,
        status: if(local_url?, do: :warn, else: :ok),
        detail:
          if(local_url?,
            do: "HYDRA_X_PUBLIC_URL is still local: #{public_url}",
            else: public_url
          )
      },
      %{
        id: "backups",
        label: "Backups are being written",
        required: true,
        status: if(backups.latest_backup, do: :ok, else: :warn),
        detail:
          if(backups.latest_backup,
            do: backups.latest_backup["archive_path"],
            else: "no backup manifest found in #{backup_root}"
          )
      },
      %{
        id: "provider",
        label: "Primary provider configured",
        required: false,
        status: if(enabled_provider(), do: :ok, else: :warn),
        detail:
          case enabled_provider() do
            nil -> "mock fallback only"
            provider -> "#{provider.kind}: #{provider.model}"
          end
      },
      %{
        id: "telegram",
        label: "Telegram ingress configured",
        required: false,
        status: if(telegram.configured and telegram.enabled, do: :ok, else: :warn),
        detail:
          cond do
            telegram.configured and telegram.enabled ->
              (telegram.bot_username && "@#{telegram.bot_username}") || "configured"

            telegram.configured ->
              "saved but disabled"

            true ->
              "not configured"
          end
      },
      %{
        id: "scheduler",
        label: "Scheduler has jobs",
        required: false,
        status: if(list_scheduled_jobs(limit: 1) == [], do: :warn, else: :ok),
        detail:
          case list_scheduled_jobs(limit: 5) do
            [] -> "no scheduled jobs configured"
            jobs -> "#{length(jobs)} jobs configured"
          end
      },
      %{
        id: "memory_conflicts",
        label: "Memory conflicts are triaged",
        required: false,
        status: if(Map.get(memory_status.counts, "conflicted", 0) > 0, do: :warn, else: :ok),
        detail:
          case Map.get(memory_status.counts, "conflicted", 0) do
            0 -> "no conflicted memories pending"
            count -> "#{count} conflicted memories need review"
          end
      },
      %{
        id: "tool_policy",
        label: "Tool policy reviewed",
        required: false,
        status:
          if(tool_policy.shell_command_enabled or tool_policy.http_allowlist != [],
            do: :ok,
            else: :warn
          ),
        detail:
          "shell #{enabled_text(tool_policy.shell_command_enabled)}; http allowlist #{describe_allowlist(tool_policy.http_allowlist)}"
      }
    ]

    items =
      items
      |> maybe_filter_readiness_required(Keyword.get(opts, :required_only, false))
      |> maybe_filter_readiness_status(Keyword.get(opts, :status))
      |> maybe_filter_readiness_search(Keyword.get(opts, :search))

    %{
      summary:
        if(Enum.any?(items, &(&1.required and &1.status != :ok)),
          do: :warn,
          else: :ok
        ),
      items: items
    }
  end

  def install_snapshot do
    public_url = Config.public_base_url()
    uri = URI.parse(public_url)

    %{
      generated_at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      public_url: public_url,
      phx_host: uri.host || "localhost",
      port: uri.port || default_port(uri.scheme),
      database_path: Config.repo_database_path(),
      workspace_root: Config.workspace_root(),
      backup_root: Config.backup_root(),
      http_allowlist: Config.http_allowlist(),
      shell_allowlist: Config.shell_allowlist(),
      readiness: readiness_report()
    }
  end

  def backup_status do
    root = Config.backup_root()
    manifests = HydraX.Backup.list_manifests(root)

    %{
      root: root,
      latest_backup: List.first(manifests),
      recent_backups: Enum.take(manifests, 5)
    }
  end

  defp tool_detail(tool_status) do
    shell = Enum.join(tool_status.shell_allowlist, ", ")

    http =
      case tool_status.http_allowlist do
        [] -> "public hosts"
        hosts -> Enum.join(hosts, ", ")
      end

    "workspace read #{enabled_text(tool_status.workspace_guard)}; http fetch #{enabled_text(tool_status.url_guard)}; shell #{enabled_text(tool_status.shell_command_enabled)}; shell allowlist: #{shell}; http allowlist: #{http}"
  end

  defp describe_allowlist([]), do: "public hosts"
  defp describe_allowlist(hosts), do: Enum.join(hosts, ", ")

  defp default_port("https"), do: 443
  defp default_port(_scheme), do: 4000

  defp provider_module(%ProviderConfig{kind: "openai_compatible"}),
    do: HydraX.LLM.Providers.OpenAICompatible

  defp provider_module(%ProviderConfig{kind: "anthropic"}), do: HydraX.LLM.Providers.Anthropic

  defp maybe_put_request_fn(request, opts) do
    case Keyword.get(opts, :request_fn) do
      nil -> request
      request_fn -> Map.put(request, :request_fn, request_fn)
    end
  end

  defp maybe_put_request_fn_from_config(request) do
    case Application.get_env(:hydra_x, :provider_test_request_fn) do
      nil -> request
      request_fn -> Map.put(request, :request_fn, request_fn)
    end
  end

  defp execute_scheduled_job(%ScheduledJob{kind: "heartbeat"} = job) do
    with {:ok, agent} <- fetch_job_agent(job),
         heartbeat <- Workspace.load_context(agent.workspace_root)["HEARTBEAT.md"] || "" do
      prompt =
        [
          job.prompt ||
            "Run the heartbeat routine for this workspace and report anything that needs operator attention.",
          heartbeat
        ]
        |> Enum.reject(&(&1 in [nil, ""]))
        |> Enum.join("\n\n")

      run_job_prompt(agent, job, prompt)
    end
  end

  defp execute_scheduled_job(%ScheduledJob{kind: "prompt"} = job) do
    with {:ok, agent} <- fetch_job_agent(job) do
      run_job_prompt(agent, job, job.prompt || "Scheduled prompt job.")
    end
  end

  defp execute_scheduled_job(%ScheduledJob{kind: "backup"} = _job) do
    with {:ok, manifest} <- HydraX.Backup.create_bundle(Config.backup_root()) do
      {:ok, "Created backup bundle at #{manifest["archive_path"]}",
       %{
         "archive_path" => manifest["archive_path"],
         "manifest_path" => manifest["manifest_path"],
         "entry_count" => manifest["entry_count"]
       }}
    end
  end

  defp run_job_prompt(agent, job, prompt) do
    with {:ok, _pid} <- HydraX.Agent.ensure_started(agent),
         {:ok, conversation} <-
           start_conversation(agent, %{
             channel: "scheduler",
             title: "#{job.name} #{Calendar.strftime(DateTime.utc_now(), "%Y-%m-%d %H:%M")}",
             metadata: %{"scheduled_job_id" => job.id, "kind" => job.kind}
           }) do
      output =
        try do
          HydraX.Agent.Channel.submit(
            agent,
            conversation,
            prompt,
            %{source: "scheduler", scheduled_job_id: job.id}
          )
        rescue
          error -> {:error, Exception.message(error)}
        catch
          kind, reason -> {:error, "#{kind}: #{inspect(reason)}"}
        end

      case output do
        {:error, reason} -> {:error, reason}
        text -> {:ok, text, %{"conversation_id" => conversation.id}}
      end
    end
  end

  defp fetch_job_agent(job) do
    case Repo.get(AgentProfile, job.agent_id) do
      nil -> {:error, :agent_not_found}
      agent -> {:ok, agent}
    end
  end

  defp ensure_named_job!(agent_id, kind, name, attrs) do
    jobs =
      ScheduledJob
      |> where([job], job.agent_id == ^agent_id and job.kind == ^kind and job.name == ^name)
      |> order_by([job], asc: job.inserted_at, asc: job.id)
      |> Repo.all()

    case jobs do
      [] ->
        {:ok, job} =
          save_scheduled_job(
            Map.merge(attrs, %{
              agent_id: agent_id,
              name: name,
              kind: kind
            })
          )

        job

      [job | rest] ->
        Enum.each(rest, &Repo.delete!/1)

        {:ok, job} =
          save_scheduled_job(job, %{
            interval_minutes: attrs[:interval_minutes],
            enabled: attrs[:enabled]
          })

        job
    end
  end

  defp next_run_at(%ScheduledJob{} = job), do: next_run_at(job, DateTime.utc_now())
  defp next_run_at(interval_minutes), do: next_run_at(interval_minutes, DateTime.utc_now())

  defp next_run_at(%ScheduledJob{schedule_mode: "daily"} = job, from) do
    next_daily_run_at(job.run_hour, job.run_minute, from)
  end

  defp next_run_at(%ScheduledJob{schedule_mode: "weekly"} = job, from) do
    next_weekly_run_at(job.weekday_csv, job.run_hour, job.run_minute, from)
  end

  defp next_run_at(%ScheduledJob{} = job, from) do
    next_interval_run_at(job.interval_minutes || 60, from)
  end

  defp next_run_at(interval_minutes, from) do
    next_interval_run_at(interval_minutes, from)
  end

  defp next_interval_run_at(interval_minutes, from) do
    DateTime.add(from, interval_minutes * 60, :second)
  end

  defp next_daily_run_at(run_hour, run_minute, from) do
    time = Time.new!(run_hour || 0, run_minute || 0, 0)
    date = DateTime.to_date(from)
    {:ok, naive} = NaiveDateTime.new(date, time)
    candidate = DateTime.from_naive!(naive, "Etc/UTC")

    if DateTime.compare(candidate, from) == :gt do
      candidate
    else
      {:ok, next_naive} = NaiveDateTime.new(Date.add(date, 1), time)
      DateTime.from_naive!(next_naive, "Etc/UTC")
    end
  end

  defp next_weekly_run_at(weekday_csv, run_hour, run_minute, from) do
    weekdays = parse_weekdays(weekday_csv)
    current_date = DateTime.to_date(from)

    candidates =
      0..7
      |> Enum.map(fn offset ->
        date = Date.add(current_date, offset)

        if Date.day_of_week(date) in weekdays do
          {:ok, naive} = NaiveDateTime.new(date, Time.new!(run_hour || 0, run_minute || 0, 0))
          DateTime.from_naive!(naive, "Etc/UTC")
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.filter(&(DateTime.compare(&1, from) == :gt))

    List.first(candidates) ||
      next_weekly_run_at(
        weekday_csv,
        run_hour,
        run_minute,
        DateTime.add(from, 7 * 86_400, :second)
      )
  end

  defp enabled_text(true), do: "enabled"
  defp enabled_text(false), do: "disabled"

  defp csv_values(nil, fallback), do: fallback
  defp csv_values("", fallback), do: fallback

  defp csv_values(csv, _fallback) do
    csv
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp format_alarm({:system_memory_high_watermark, _details}), do: "system memory high watermark"

  defp format_alarm({{:disk_almost_full, path}, _details}),
    do: "disk almost full at #{List.to_string(path)}"

  defp format_alarm({alarm, _details}), do: inspect(alarm)
  defp format_alarm(alarm), do: inspect(alarm)

  defp local_public_url?(url) do
    case URI.parse(url) do
      %URI{host: host} when host in [nil, "", "localhost", "127.0.0.1"] -> true
      %URI{host: host} when is_binary(host) -> String.ends_with?(host, ".local")
      _ -> true
    end
  end

  defp normalize_integer(nil), do: nil
  defp normalize_integer(""), do: nil
  defp normalize_integer(value) when is_integer(value), do: value
  defp normalize_integer(value) when is_binary(value), do: String.to_integer(value)

  defp persisted_integer(attrs, key, fallback) do
    if Map.has_key?(attrs, key) do
      normalize_integer(Map.get(attrs, key))
    else
      fallback
    end
  end

  defp normalize_weekday_csv(nil), do: nil
  defp normalize_weekday_csv(""), do: nil

  defp normalize_weekday_csv(value) when is_binary(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.map(&String.downcase/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.join(",")
  end

  defp persisted_weekday_csv(attrs, key, fallback) do
    if Map.has_key?(attrs, key) do
      normalize_weekday_csv(Map.get(attrs, key))
    else
      fallback
    end
  end

  defp parse_weekdays(nil), do: [1]
  defp parse_weekdays(""), do: [1]

  defp parse_weekdays(csv) do
    weekday_map = %{
      "mon" => 1,
      "tue" => 2,
      "wed" => 3,
      "thu" => 4,
      "fri" => 5,
      "sat" => 6,
      "sun" => 7
    }

    csv
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.map(&String.downcase/1)
    |> Enum.map(&Map.get(weekday_map, &1))
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> [1]
      weekdays -> weekdays
    end
  end

  defp retry_on_busy(fun, attempts \\ 5)

  defp retry_on_busy(fun, attempts) do
    fun.()
  rescue
    error in Exqlite.Error ->
      if attempts > 1 and String.contains?(Exception.message(error), "Database busy") do
        Process.sleep(50)
        retry_on_busy(fun, attempts - 1)
      else
        reraise error, __STACKTRACE__
      end
  end

  defp maybe_filter_agent(query, nil), do: query

  defp maybe_filter_agent(query, agent_id),
    do: where(query, [conversation], conversation.agent_id == ^agent_id)

  defp maybe_filter_conversation_status(query, nil), do: query
  defp maybe_filter_conversation_status(query, ""), do: query

  defp maybe_filter_conversation_status(query, status),
    do: where(query, [conversation], conversation.status == ^status)

  defp maybe_filter_conversation_channel(query, nil), do: query
  defp maybe_filter_conversation_channel(query, ""), do: query

  defp maybe_filter_conversation_channel(query, channel),
    do: where(query, [conversation], conversation.channel == ^channel)

  defp maybe_filter_conversation_search(query, nil), do: query
  defp maybe_filter_conversation_search(query, ""), do: query

  defp maybe_filter_conversation_search(query, search) do
    pattern = "%#{search}%"

    where(
      query,
      [conversation],
      like(conversation.title, ^pattern) or like(conversation.external_ref, ^pattern)
    )
  end

  defp maybe_filter_scheduled_job_agent(query, nil), do: query

  defp maybe_filter_scheduled_job_agent(query, agent_id),
    do: where(query, [job], job.agent_id == ^agent_id)

  defp maybe_filter_scheduled_job_kind(query, nil), do: query
  defp maybe_filter_scheduled_job_kind(query, ""), do: query
  defp maybe_filter_scheduled_job_kind(query, kind), do: where(query, [job], job.kind == ^kind)

  defp maybe_filter_scheduled_job_enabled(query, nil), do: query

  defp maybe_filter_scheduled_job_enabled(query, enabled) when is_boolean(enabled),
    do: where(query, [job], job.enabled == ^enabled)

  defp maybe_filter_scheduled_job_enabled(query, ""), do: query

  defp maybe_filter_scheduled_job_search(query, nil), do: query
  defp maybe_filter_scheduled_job_search(query, ""), do: query

  defp maybe_filter_scheduled_job_search(query, search) do
    pattern = "%#{search}%"

    where(
      query,
      [job],
      like(job.name, ^pattern) or like(job.prompt, ^pattern)
    )
  end

  defp maybe_filter_check_status(checks, nil), do: checks
  defp maybe_filter_check_status(checks, ""), do: checks

  defp maybe_filter_check_status(checks, status) do
    Enum.filter(checks, &(Atom.to_string(&1.status) == to_string(status)))
  end

  defp maybe_filter_check_search(checks, nil), do: checks
  defp maybe_filter_check_search(checks, ""), do: checks

  defp maybe_filter_check_search(checks, search) do
    downcased = String.downcase(search)

    Enum.filter(checks, fn check ->
      String.contains?(String.downcase(check.name), downcased) or
        String.contains?(String.downcase(check.detail), downcased)
    end)
  end

  defp maybe_filter_readiness_required(items, true), do: Enum.filter(items, & &1.required)
  defp maybe_filter_readiness_required(items, _), do: items

  defp maybe_filter_readiness_status(items, nil), do: items
  defp maybe_filter_readiness_status(items, ""), do: items

  defp maybe_filter_readiness_status(items, status) do
    Enum.filter(items, &(Atom.to_string(&1.status) == to_string(status)))
  end

  defp maybe_filter_readiness_search(items, nil), do: items
  defp maybe_filter_readiness_search(items, ""), do: items

  defp maybe_filter_readiness_search(items, search) do
    downcased = String.downcase(search)

    Enum.filter(items, fn item ->
      String.contains?(String.downcase(item.label), downcased) or
        String.contains?(String.downcase(item.detail), downcased)
    end)
  end

  defp normalize_agent_attrs(attrs) do
    normalized = normalize_string_keys(attrs)

    cond do
      Map.has_key?(normalized, "workspace_root") ->
        normalized

      is_binary(normalized["slug"]) and normalized["slug"] != "" ->
        Map.put(normalized, "workspace_root", Config.default_workspace(normalized["slug"]))

      true ->
        normalized
    end
  end

  defp normalize_compaction_policy(attrs) do
    defaults = Config.compaction_thresholds()
    normalized = normalize_string_keys(attrs)

    %{
      soft: map_integer(normalized["soft"], defaults.soft),
      medium: map_integer(normalized["medium"], defaults.medium),
      hard: map_integer(normalized["hard"], defaults.hard)
    }
  end

  defp validate_compaction_policy!(%{soft: soft, medium: medium, hard: hard}) do
    cond do
      soft < 1 or medium < 1 or hard < 1 ->
        raise ArgumentError, "compaction thresholds must be positive integers"

      not (soft < medium and medium < hard) ->
        raise ArgumentError, "compaction thresholds must satisfy soft < medium < hard"

      true ->
        :ok
    end
  end

  defp transcript_path(agent, conversation) do
    safe_title =
      (conversation.title || "conversation")
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/u, "-")
      |> String.trim("-")
      |> case do
        "" -> "conversation"
        value -> value
      end

    Path.join([
      agent.workspace_root,
      "transcripts",
      "#{conversation.id}-#{safe_title}.md"
    ])
  end

  defp render_transcript(conversation) do
    header = [
      "# #{conversation.title || "Untitled conversation"}",
      "",
      "- id: #{conversation.id}",
      "- channel: #{conversation.channel}",
      "- status: #{conversation.status}",
      "- updated_at: #{Calendar.strftime(conversation.updated_at, "%Y-%m-%d %H:%M UTC")}",
      ""
    ]

    turns =
      Enum.map(conversation.turns, fn turn ->
        [
          "## #{String.capitalize(turn.role)} ##{turn.sequence}",
          "",
          turn.content,
          ""
        ]
      end)

    [header | turns]
    |> List.flatten()
    |> Enum.join("\n")
  end

  defp normalize_string_keys(attrs) do
    Enum.reduce(attrs, %{}, fn
      {key, value}, acc when is_atom(key) -> Map.put(acc, Atom.to_string(key), value)
      {key, value}, acc -> Map.put(acc, key, value)
    end)
  end

  defp map_integer(nil, default), do: default
  defp map_integer("", default), do: default
  defp map_integer(value, _default) when is_integer(value), do: value
  defp map_integer(value, _default) when is_binary(value), do: String.to_integer(value)

  defp unwrap_transaction({:ok, value}), do: {:ok, value}
  defp unwrap_transaction({:error, reason}), do: {:error, reason}
end
