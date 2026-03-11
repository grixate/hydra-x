defmodule HydraX.Runtime do
  @moduledoc """
  Thin facade delegating to domain-specific sub-modules.

  All public functions are preserved for backward compatibility.
  Operator authentication functions are defined directly here.
  """

  alias HydraX.Repo
  alias HydraX.Runtime.Helpers
  alias HydraX.Runtime.OperatorSecret

  # ── Agents ──────────────────────────────────────────────────────────────

  defdelegate list_agents(), to: HydraX.Runtime.Agents
  defdelegate get_agent!(id), to: HydraX.Runtime.Agents
  defdelegate get_agent_by_slug(slug), to: HydraX.Runtime.Agents
  defdelegate get_default_agent(), to: HydraX.Runtime.Agents
  defdelegate ensure_default_agent!(), to: HydraX.Runtime.Agents
  defdelegate change_agent(), to: HydraX.Runtime.Agents
  defdelegate change_agent(agent), to: HydraX.Runtime.Agents
  defdelegate change_agent(agent, attrs), to: HydraX.Runtime.Agents
  defdelegate save_agent(attrs), to: HydraX.Runtime.Agents
  defdelegate save_agent(agent, attrs), to: HydraX.Runtime.Agents
  defdelegate update_agent_runtime_state(agent, attrs), to: HydraX.Runtime.Agents
  defdelegate toggle_agent_status!(id), to: HydraX.Runtime.Agents
  defdelegate set_default_agent!(id), to: HydraX.Runtime.Agents
  defdelegate repair_agent_workspace!(id), to: HydraX.Runtime.Agents
  defdelegate agent_bulletin(id), to: HydraX.Runtime.Agents
  defdelegate compaction_policy(id), to: HydraX.Runtime.Agents
  defdelegate save_compaction_policy!(id, attrs), to: HydraX.Runtime.Agents
  defdelegate refresh_agent_bulletin!(id), to: HydraX.Runtime.Agents
  defdelegate agent_runtime_status(agent_or_id), to: HydraX.Runtime.Agents
  defdelegate start_agent_runtime!(id), to: HydraX.Runtime.Agents
  defdelegate stop_agent_runtime!(id), to: HydraX.Runtime.Agents
  defdelegate restart_agent_runtime!(id), to: HydraX.Runtime.Agents
  defdelegate reconcile_agents!(), to: HydraX.Runtime.Agents

  # ── Providers ───────────────────────────────────────────────────────────

  defdelegate list_provider_configs(), to: HydraX.Runtime.Providers
  defdelegate get_provider_config!(id), to: HydraX.Runtime.Providers
  defdelegate enabled_provider(), to: HydraX.Runtime.Providers
  defdelegate enabled_provider(agent_id, process_type), to: HydraX.Runtime.Providers

  defdelegate effective_provider_route(agent_id, process_type),
    to: HydraX.Runtime.EffectivePolicy

  defdelegate effective_provider_route(agent_id, process_type, opts),
    to: HydraX.Runtime.EffectivePolicy

  defdelegate effective_policy(), to: HydraX.Runtime.EffectivePolicy
  defdelegate effective_policy(agent_id), to: HydraX.Runtime.EffectivePolicy
  defdelegate effective_policy(agent_id, opts), to: HydraX.Runtime.EffectivePolicy
  defdelegate provider_routing_profile(agent_id), to: HydraX.Runtime.Providers
  defdelegate save_agent_provider_routing(agent_id, attrs), to: HydraX.Runtime.Providers
  defdelegate clear_agent_provider_routing!(agent_id), to: HydraX.Runtime.Providers
  defdelegate warm_agent_provider_routing(agent_id), to: HydraX.Runtime.Providers
  defdelegate warm_agent_provider_routing(agent_id, opts), to: HydraX.Runtime.Providers
  defdelegate provider_capabilities(provider), to: HydraX.Runtime.Providers
  defdelegate provider_health(provider), to: HydraX.Runtime.Providers
  defdelegate provider_health(provider, opts), to: HydraX.Runtime.Providers
  defdelegate change_provider_config(), to: HydraX.Runtime.Providers
  defdelegate change_provider_config(provider), to: HydraX.Runtime.Providers
  defdelegate change_provider_config(provider, attrs), to: HydraX.Runtime.Providers
  defdelegate save_provider_config(attrs), to: HydraX.Runtime.Providers
  defdelegate save_provider_config(provider, attrs), to: HydraX.Runtime.Providers
  defdelegate activate_provider!(id), to: HydraX.Runtime.Providers
  defdelegate toggle_provider_enabled!(id), to: HydraX.Runtime.Providers
  defdelegate delete_provider_config!(id), to: HydraX.Runtime.Providers
  defdelegate get_tool_policy(), to: HydraX.Runtime.Providers
  defdelegate ensure_tool_policy!(), to: HydraX.Runtime.Providers
  defdelegate change_tool_policy(), to: HydraX.Runtime.Providers
  defdelegate change_tool_policy(policy), to: HydraX.Runtime.Providers
  defdelegate change_tool_policy(policy, attrs), to: HydraX.Runtime.Providers
  defdelegate save_tool_policy(attrs), to: HydraX.Runtime.Providers
  defdelegate save_tool_policy(policy, attrs), to: HydraX.Runtime.Providers
  defdelegate effective_tool_policy(), to: HydraX.Runtime.Providers
  defdelegate effective_tool_policy(agent_id), to: HydraX.Runtime.Providers
  defdelegate get_agent_tool_policy(agent_id), to: HydraX.Runtime.Providers
  defdelegate save_agent_tool_policy(agent_id, attrs), to: HydraX.Runtime.Providers
  defdelegate delete_agent_tool_policy!(agent_id), to: HydraX.Runtime.Providers
  defdelegate test_provider_config(provider), to: HydraX.Runtime.Providers
  defdelegate test_provider_config(provider, opts), to: HydraX.Runtime.Providers

  # ── Control policy ───────────────────────────────────────────────────────

  defdelegate get_control_policy(), to: HydraX.Runtime.ControlPolicies
  defdelegate ensure_control_policy!(), to: HydraX.Runtime.ControlPolicies
  defdelegate change_control_policy(), to: HydraX.Runtime.ControlPolicies
  defdelegate change_control_policy(policy), to: HydraX.Runtime.ControlPolicies
  defdelegate change_control_policy(policy, attrs), to: HydraX.Runtime.ControlPolicies
  defdelegate save_control_policy(attrs), to: HydraX.Runtime.ControlPolicies
  defdelegate save_control_policy(policy, attrs), to: HydraX.Runtime.ControlPolicies
  defdelegate effective_control_policy(), to: HydraX.Runtime.ControlPolicies
  defdelegate effective_control_policy(agent_id), to: HydraX.Runtime.ControlPolicies
  defdelegate get_agent_control_policy(agent_id), to: HydraX.Runtime.ControlPolicies
  defdelegate save_agent_control_policy(agent_id, attrs), to: HydraX.Runtime.ControlPolicies
  defdelegate delete_agent_control_policy!(agent_id), to: HydraX.Runtime.ControlPolicies

  # ── Skills ───────────────────────────────────────────────────────────────

  defdelegate list_skills(), to: HydraX.Runtime.Skills
  defdelegate list_skills(opts), to: HydraX.Runtime.Skills
  defdelegate list_skills_for_agent(agent_id), to: HydraX.Runtime.Skills
  defdelegate enabled_skills(agent_id), to: HydraX.Runtime.Skills
  defdelegate get_skill!(id), to: HydraX.Runtime.Skills
  defdelegate skill_catalog(agent_id), to: HydraX.Runtime.Skills
  defdelegate export_skill_catalog(agent_id, output_root), to: HydraX.Runtime.Skills
  defdelegate refresh_agent_skills(agent_id), to: HydraX.Runtime.Skills
  defdelegate enable_skill!(id), to: HydraX.Runtime.Skills
  defdelegate disable_skill!(id), to: HydraX.Runtime.Skills
  defdelegate skill_prompt_context(agent_id), to: HydraX.Runtime.Skills
  defdelegate skill_prompt_context(agent_id, opts), to: HydraX.Runtime.Skills

  # ── MCP ──────────────────────────────────────────────────────────────────

  defdelegate list_mcp_servers(), to: HydraX.Runtime.MCPServers
  defdelegate enabled_mcp_servers(), to: HydraX.Runtime.MCPServers
  defdelegate list_agent_mcp_servers(agent_id), to: HydraX.Runtime.MCPServers
  defdelegate list_agent_mcp_actions(agent_id), to: HydraX.Runtime.MCPServers
  defdelegate list_agent_mcp_actions(agent_id, opts), to: HydraX.Runtime.MCPServers
  defdelegate enabled_mcp_servers(agent_id), to: HydraX.Runtime.MCPServers
  defdelegate get_agent_mcp_server!(id), to: HydraX.Runtime.MCPServers
  defdelegate get_mcp_server!(id), to: HydraX.Runtime.MCPServers
  defdelegate change_mcp_server(), to: HydraX.Runtime.MCPServers
  defdelegate change_mcp_server(config), to: HydraX.Runtime.MCPServers
  defdelegate change_mcp_server(config, attrs), to: HydraX.Runtime.MCPServers
  defdelegate save_mcp_server(attrs), to: HydraX.Runtime.MCPServers
  defdelegate save_mcp_server(config, attrs), to: HydraX.Runtime.MCPServers
  defdelegate delete_mcp_server!(id), to: HydraX.Runtime.MCPServers
  defdelegate mcp_statuses(), to: HydraX.Runtime.MCPServers
  defdelegate agent_mcp_statuses(), to: HydraX.Runtime.MCPServers
  defdelegate agent_mcp_statuses(agent_id), to: HydraX.Runtime.MCPServers
  defdelegate mcp_prompt_context(), to: HydraX.Runtime.MCPServers
  defdelegate mcp_prompt_context(agent_id), to: HydraX.Runtime.MCPServers
  defdelegate refresh_agent_mcp_servers(agent_id), to: HydraX.Runtime.MCPServers
  defdelegate enable_agent_mcp_server!(id), to: HydraX.Runtime.MCPServers
  defdelegate disable_agent_mcp_server!(id), to: HydraX.Runtime.MCPServers
  defdelegate test_mcp_server(config), to: HydraX.Runtime.MCPServers
  defdelegate test_mcp_server(config, opts), to: HydraX.Runtime.MCPServers
  defdelegate invoke_agent_mcp(agent_id, action, params), to: HydraX.Runtime.MCPServers
  defdelegate invoke_agent_mcp(agent_id, action, params, opts), to: HydraX.Runtime.MCPServers

  # ── Conversations ───────────────────────────────────────────────────────

  defdelegate list_conversations(), to: HydraX.Runtime.Conversations
  defdelegate list_conversations(opts), to: HydraX.Runtime.Conversations
  defdelegate get_conversation!(id), to: HydraX.Runtime.Conversations
  defdelegate find_conversation(agent_id, channel, external_ref), to: HydraX.Runtime.Conversations
  defdelegate start_conversation(agent), to: HydraX.Runtime.Conversations
  defdelegate start_conversation(agent, attrs), to: HydraX.Runtime.Conversations
  defdelegate save_conversation(conversation, attrs), to: HydraX.Runtime.Conversations
  defdelegate archive_conversation!(id), to: HydraX.Runtime.Conversations
  defdelegate conversation_compaction(id), to: HydraX.Runtime.Conversations
  defdelegate conversation_channel_state(id), to: HydraX.Runtime.Conversations
  defdelegate review_conversation_compaction!(id), to: HydraX.Runtime.Conversations
  defdelegate reset_conversation_compaction!(id), to: HydraX.Runtime.Conversations
  defdelegate export_conversation_transcript!(id), to: HydraX.Runtime.Conversations
  defdelegate list_turns(conversation_id), to: HydraX.Runtime.Conversations
  defdelegate append_turn(conversation, attrs), to: HydraX.Runtime.Conversations
  defdelegate list_owned_resumable_conversations(opts), to: HydraX.Runtime.Conversations
  defdelegate list_owned_pending_deliveries(opts), to: HydraX.Runtime.Conversations
  defdelegate resume_owned_conversations(), to: HydraX.Runtime.Conversations
  defdelegate resume_owned_conversations(opts), to: HydraX.Runtime.Conversations
  defdelegate get_checkpoint(conversation_id, process_type), to: HydraX.Runtime.Conversations

  defdelegate upsert_checkpoint(conversation_id, process_type, state),
    to: HydraX.Runtime.Conversations

  defdelegate update_conversation_metadata(conversation, attrs), to: HydraX.Runtime.Conversations

  # ── Coordination ────────────────────────────────────────────────────────

  defdelegate claim_lease(name), to: HydraX.Runtime.Coordination
  defdelegate claim_lease(name, opts), to: HydraX.Runtime.Coordination
  defdelegate release_lease(name), to: HydraX.Runtime.Coordination
  defdelegate release_lease(name, opts), to: HydraX.Runtime.Coordination
  defdelegate get_lease(name), to: HydraX.Runtime.Coordination
  defdelegate active_lease(name), to: HydraX.Runtime.Coordination
  defdelegate list_active_leases(), to: HydraX.Runtime.Coordination
  defdelegate coordination_status(), to: HydraX.Runtime.Coordination, as: :status

  # ── Jobs ────────────────────────────────────────────────────────────────

  defdelegate list_scheduled_jobs(), to: HydraX.Runtime.Jobs
  defdelegate list_scheduled_jobs(opts), to: HydraX.Runtime.Jobs
  defdelegate get_scheduled_job!(id), to: HydraX.Runtime.Jobs
  defdelegate change_scheduled_job(), to: HydraX.Runtime.Jobs
  defdelegate change_scheduled_job(job), to: HydraX.Runtime.Jobs
  defdelegate change_scheduled_job(job, attrs), to: HydraX.Runtime.Jobs
  defdelegate save_scheduled_job(attrs), to: HydraX.Runtime.Jobs
  defdelegate save_scheduled_job(job, attrs), to: HydraX.Runtime.Jobs
  defdelegate parse_schedule_text(text), to: HydraX.Runtime.Jobs
  defdelegate schedule_text_for(job), to: HydraX.Runtime.Jobs
  defdelegate delete_scheduled_job!(id), to: HydraX.Runtime.Jobs
  defdelegate list_due_scheduled_jobs(now), to: HydraX.Runtime.Jobs
  def recent_job_runs(), do: HydraX.Runtime.Jobs.recent_job_runs()

  def recent_job_runs(limit) when is_integer(limit),
    do: HydraX.Runtime.Jobs.recent_job_runs(limit)

  def recent_job_runs(opts) when is_list(opts), do: HydraX.Runtime.Jobs.recent_job_runs(opts)
  defdelegate recent_job_runs_by_status(status), to: HydraX.Runtime.Jobs
  defdelegate recent_job_runs_by_status(status, limit), to: HydraX.Runtime.Jobs
  def list_job_runs(job_id) when is_integer(job_id), do: HydraX.Runtime.Jobs.list_job_runs(job_id)
  def list_job_runs(opts) when is_list(opts), do: HydraX.Runtime.Jobs.list_job_runs(opts)

  def list_job_runs(job_id, limit) when is_integer(job_id),
    do: HydraX.Runtime.Jobs.list_job_runs(job_id, limit)

  defdelegate open_circuit_jobs(), to: HydraX.Runtime.Jobs
  defdelegate open_circuit_jobs(limit), to: HydraX.Runtime.Jobs
  defdelegate delete_old_job_runs(), to: HydraX.Runtime.Jobs
  defdelegate delete_old_job_runs(max_age_days), to: HydraX.Runtime.Jobs
  defdelegate ensure_heartbeat_job!(agent_id), to: HydraX.Runtime.Jobs
  defdelegate ensure_backup_job!(agent_id), to: HydraX.Runtime.Jobs
  defdelegate ensure_default_jobs!(), to: HydraX.Runtime.Jobs
  defdelegate run_scheduled_job(job), to: HydraX.Runtime.Jobs
  defdelegate reset_scheduled_job_circuit!(id), to: HydraX.Runtime.Jobs
  defdelegate scheduler_status(), to: HydraX.Runtime.Jobs
  defdelegate job_stats(), to: HydraX.Runtime.Jobs
  defdelegate job_stats(limit), to: HydraX.Runtime.Jobs
  defdelegate export_job_runs(output_root), to: HydraX.Runtime.Jobs
  defdelegate export_job_runs(output_root, opts), to: HydraX.Runtime.Jobs

  # ── Telegram ────────────────────────────────────────────────────────────

  defdelegate enabled_telegram_config(), to: HydraX.Runtime.TelegramAdmin
  defdelegate list_telegram_configs(), to: HydraX.Runtime.TelegramAdmin
  defdelegate change_telegram_config(), to: HydraX.Runtime.TelegramAdmin
  defdelegate change_telegram_config(config), to: HydraX.Runtime.TelegramAdmin
  defdelegate change_telegram_config(config, attrs), to: HydraX.Runtime.TelegramAdmin
  defdelegate save_telegram_config(attrs), to: HydraX.Runtime.TelegramAdmin
  defdelegate save_telegram_config(config, attrs), to: HydraX.Runtime.TelegramAdmin
  defdelegate register_telegram_webhook(config), to: HydraX.Runtime.TelegramAdmin
  defdelegate register_telegram_webhook(config, opts), to: HydraX.Runtime.TelegramAdmin
  defdelegate sync_telegram_webhook_info(config), to: HydraX.Runtime.TelegramAdmin
  defdelegate sync_telegram_webhook_info(config, opts), to: HydraX.Runtime.TelegramAdmin
  defdelegate delete_telegram_webhook(config), to: HydraX.Runtime.TelegramAdmin
  defdelegate delete_telegram_webhook(config, opts), to: HydraX.Runtime.TelegramAdmin
  defdelegate test_telegram_delivery(config, target, message), to: HydraX.Runtime.TelegramAdmin

  defdelegate test_telegram_delivery(config, target, message, opts),
    to: HydraX.Runtime.TelegramAdmin

  # ── Discord ───────────────────────────────────────────────────────────

  defdelegate enabled_discord_config(), to: HydraX.Runtime.DiscordAdmin
  defdelegate list_discord_configs(), to: HydraX.Runtime.DiscordAdmin
  defdelegate change_discord_config(), to: HydraX.Runtime.DiscordAdmin
  defdelegate change_discord_config(config), to: HydraX.Runtime.DiscordAdmin
  defdelegate change_discord_config(config, attrs), to: HydraX.Runtime.DiscordAdmin
  defdelegate save_discord_config(attrs), to: HydraX.Runtime.DiscordAdmin
  defdelegate save_discord_config(config, attrs), to: HydraX.Runtime.DiscordAdmin
  defdelegate test_discord_delivery(config, target, message), to: HydraX.Runtime.DiscordAdmin

  defdelegate test_discord_delivery(config, target, message, opts),
    to: HydraX.Runtime.DiscordAdmin

  # ── Slack ────────────────────────────────────────────────────────────

  defdelegate enabled_slack_config(), to: HydraX.Runtime.SlackAdmin
  defdelegate list_slack_configs(), to: HydraX.Runtime.SlackAdmin
  defdelegate change_slack_config(), to: HydraX.Runtime.SlackAdmin
  defdelegate change_slack_config(config), to: HydraX.Runtime.SlackAdmin
  defdelegate change_slack_config(config, attrs), to: HydraX.Runtime.SlackAdmin
  defdelegate save_slack_config(attrs), to: HydraX.Runtime.SlackAdmin
  defdelegate save_slack_config(config, attrs), to: HydraX.Runtime.SlackAdmin
  defdelegate test_slack_delivery(config, target, message), to: HydraX.Runtime.SlackAdmin
  defdelegate test_slack_delivery(config, target, message, opts), to: HydraX.Runtime.SlackAdmin

  # ── Webchat ──────────────────────────────────────────────────────────

  defdelegate enabled_webchat_config(), to: HydraX.Runtime.WebchatAdmin
  defdelegate list_webchat_configs(), to: HydraX.Runtime.WebchatAdmin
  defdelegate change_webchat_config(), to: HydraX.Runtime.WebchatAdmin
  defdelegate change_webchat_config(config), to: HydraX.Runtime.WebchatAdmin
  defdelegate change_webchat_config(config, attrs), to: HydraX.Runtime.WebchatAdmin
  defdelegate save_webchat_config(attrs), to: HydraX.Runtime.WebchatAdmin
  defdelegate save_webchat_config(config, attrs), to: HydraX.Runtime.WebchatAdmin

  # ── Observability ───────────────────────────────────────────────────────

  defdelegate health_snapshot(), to: HydraX.Runtime.Observability
  defdelegate health_snapshot(opts), to: HydraX.Runtime.Observability
  defdelegate telegram_status(), to: HydraX.Runtime.Observability
  defdelegate discord_status(), to: HydraX.Runtime.Observability
  defdelegate slack_status(), to: HydraX.Runtime.Observability
  defdelegate webchat_status(), to: HydraX.Runtime.Observability
  defdelegate channel_statuses(), to: HydraX.Runtime.Observability
  def channel_capabilities, do: HydraX.Gateway.channel_capabilities()
  defdelegate cluster_status(), to: HydraX.Runtime.Observability
  defdelegate provider_status(), to: HydraX.Runtime.Observability
  defdelegate budget_status(), to: HydraX.Runtime.Observability
  defdelegate budget_status(agent_or_id), to: HydraX.Runtime.Observability
  defdelegate memory_triage_status(), to: HydraX.Runtime.Observability
  defdelegate memory_triage_status(agent_or_id), to: HydraX.Runtime.Observability
  defdelegate safety_status(), to: HydraX.Runtime.Observability
  defdelegate safety_status(opts), to: HydraX.Runtime.Observability
  defdelegate operator_status(), to: HydraX.Runtime.Observability
  defdelegate tool_status(), to: HydraX.Runtime.Observability
  defdelegate control_policy_status(), to: HydraX.Runtime.Observability
  defdelegate secret_storage_status(), to: HydraX.Runtime.Observability
  defdelegate observability_status(), to: HydraX.Runtime.Observability
  defdelegate system_status(), to: HydraX.Runtime.Observability
  defdelegate readiness_report(), to: HydraX.Runtime.Observability
  defdelegate readiness_report(opts), to: HydraX.Runtime.Observability
  defdelegate install_snapshot(), to: HydraX.Runtime.Observability
  defdelegate backup_status(), to: HydraX.Runtime.Observability
  defdelegate authorize_tool(agent_id, tool_name, channel), to: HydraX.Runtime.EffectivePolicy

  defdelegate authorize_tool(agent_id, tool_name, channel, opts),
    to: HydraX.Runtime.EffectivePolicy

  defdelegate tool_decision(agent_id, tool_name, channel), to: HydraX.Runtime.EffectivePolicy

  defdelegate tool_decision(agent_id, tool_name, channel, opts),
    to: HydraX.Runtime.EffectivePolicy

  defdelegate authorize_delivery(agent_id, mode, channel), to: HydraX.Runtime.EffectivePolicy

  defdelegate authorize_delivery(agent_id, mode, channel, opts),
    to: HydraX.Runtime.EffectivePolicy

  defdelegate authorize_ingest_path(agent_id, workspace_root, file_path),
    to: HydraX.Runtime.EffectivePolicy

  defdelegate authorize_ingest_path(agent_id, workspace_root, file_path, opts),
    to: HydraX.Runtime.EffectivePolicy

  defdelegate recent_auth_required?(), to: HydraX.Runtime.EffectivePolicy
  defdelegate recent_auth_required?(agent_id), to: HydraX.Runtime.EffectivePolicy
  defdelegate recent_auth_required?(agent_id, opts), to: HydraX.Runtime.EffectivePolicy

  # ── Ingest ────────────────────────────────────────────────────────────

  defdelegate ingest_file(agent_id, file_path), to: HydraX.Ingest.Pipeline
  defdelegate ingest_file(agent_id, file_path, opts), to: HydraX.Ingest.Pipeline
  defdelegate archive_file(agent_id, filename), to: HydraX.Ingest.Pipeline
  defdelegate list_ingested_files(agent_id), to: HydraX.Ingest.Pipeline
  defdelegate list_ingest_runs(agent_id), to: HydraX.Ingest.Pipeline
  defdelegate list_ingest_runs(agent_id, limit), to: HydraX.Ingest.Pipeline

  # ── Operator auth (kept in facade — small, cross-cutting) ──────────────

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
    existed_before? = operator_password_configured?()

    attrs =
      attrs
      |> HydraX.Runtime.Helpers.normalize_string_keys()
      |> Map.put_new("scope", "control_plane")

    changeset = OperatorSecret.changeset(%OperatorSecret{}, attrs)

    if changeset.valid? do
      secret = Ecto.Changeset.apply_changes(changeset)

      result =
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

      case result do
        {:ok, saved_secret} ->
          action =
            if existed_before? do
              "Rotated operator password"
            else
              "Configured operator password"
            end

          Helpers.audit_auth_action(action,
            metadata: %{
              scope: saved_secret.scope,
              rotated_at: saved_secret.last_rotated_at
            }
          )

          {:ok, saved_secret}

        other ->
          other
      end
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

  # ── Private ─────────────────────────────────────────────────────────────

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
end
