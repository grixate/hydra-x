defmodule HydraXWeb.SetupLive do
  use HydraXWeb, :live_view

  alias HydraX.Runtime
  alias HydraX.Runtime.Helpers

  alias HydraX.Runtime.{
    AgentProfile,
    DiscordConfig,
    ProviderConfig,
    SlackConfig,
    TelegramConfig,
    ToolPolicy,
    WebchatConfig
  }

  alias HydraXWeb.AppShell
  alias HydraXWeb.OperatorAuth

  @impl true
  def mount(_params, session, socket) do
    agent = Runtime.get_default_agent() || %AgentProfile{}
    operator_status = Runtime.operator_status()
    operator_session = OperatorAuth.session_state(session)

    provider =
      Runtime.enabled_provider() || List.first(Runtime.list_provider_configs()) ||
        %ProviderConfig{}

    telegram =
      Runtime.enabled_telegram_config() || List.first(Runtime.list_telegram_configs()) ||
        %TelegramConfig{default_agent_id: agent.id}

    discord =
      Runtime.enabled_discord_config() || List.first(Runtime.list_discord_configs()) ||
        %DiscordConfig{default_agent_id: agent.id}

    slack =
      Runtime.enabled_slack_config() || List.first(Runtime.list_slack_configs()) ||
        %SlackConfig{default_agent_id: agent.id}

    webchat =
      Runtime.enabled_webchat_config() || List.first(Runtime.list_webchat_configs()) ||
        %WebchatConfig{default_agent_id: agent.id}

    tool_policy = Runtime.get_tool_policy() || %ToolPolicy{}

    {:ok,
     socket
     |> assign(:page_title, "Setup")
     |> assign(:current, "setup")
     |> assign(:operator_secret, Runtime.get_operator_secret())
     |> assign(:operator_status, operator_status)
     |> assign(:operator_session, operator_session)
     |> assign(:provider_test_result, nil)
     |> assign(:telegram_test_result, nil)
     |> assign(:discord_test_result, nil)
     |> assign(:slack_test_result, nil)
     |> assign(:install_export, nil)
     |> assign(:backup_export, nil)
     |> assign(:readiness_report, Runtime.readiness_report())
     |> assign(:stats, stats())
     |> assign(:agent, agent)
     |> assign(:provider, provider)
     |> assign(:telegram, telegram)
     |> assign(:discord, discord)
     |> assign(:slack, slack)
     |> assign(:webchat, webchat)
     |> assign(:tool_policy, tool_policy)
     |> assign_form(:operator_form, Runtime.change_operator_secret())
     |> assign_form(:agent_form, Runtime.change_agent(agent))
     |> assign_form(:provider_form, Runtime.change_provider_config(provider))
     |> assign_form(:telegram_form, Runtime.change_telegram_config(telegram))
     |> assign_form(:discord_form, Runtime.change_discord_config(discord))
     |> assign_form(:slack_form, Runtime.change_slack_config(slack))
     |> assign_form(:webchat_form, Runtime.change_webchat_config(webchat))
     |> assign(:telegram_test_form, to_form(default_telegram_test(), as: :telegram_test))
     |> assign(:discord_test_form, to_form(default_channel_test("discord"), as: :discord_test))
     |> assign(:slack_test_form, to_form(default_channel_test("slack"), as: :slack_test))
     |> assign_form(:tool_policy_form, Runtime.change_tool_policy(tool_policy))}
  end

  @impl true
  def handle_event("save_agent", %{"agent_profile" => params}, socket) do
    case Runtime.save_agent(socket.assigns.agent, params) do
      {:ok, agent} ->
        HydraX.Agent.ensure_started(agent)

        {:noreply,
         socket
         |> put_flash(:info, "Agent updated")
         |> assign(:agent, agent)
         |> assign(:readiness_report, Runtime.readiness_report())
         |> assign(:stats, stats())
         |> assign_form(:agent_form, Runtime.change_agent(agent))}

      {:error, changeset} ->
        {:noreply, assign_form(socket, :agent_form, changeset)}
    end
  end

  def handle_event("save_provider", %{"provider_config" => params}, socket) do
    with {:ok, socket} <- require_recent_auth(socket, "save provider secrets"),
         {:ok, provider} <- Runtime.save_provider_config(socket.assigns.provider, params) do
      {:noreply,
       socket
       |> put_flash(:info, "Provider updated")
       |> assign(:provider, provider)
       |> assign(:readiness_report, Runtime.readiness_report())
       |> assign(:stats, stats())
       |> assign_form(:provider_form, Runtime.change_provider_config(provider))}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, :provider_form, changeset)}

      {:reauth, socket} ->
        {:noreply, socket}
    end
  end

  def handle_event("test_provider", _params, %{assigns: %{provider: %{id: nil}}} = socket) do
    {:noreply, put_flash(socket, :error, "Save the provider before testing it.")}
  end

  def handle_event("test_provider", _params, socket) do
    provider = Runtime.get_provider_config!(socket.assigns.provider.id)

    case Runtime.test_provider_config(provider) do
      {:ok, result} ->
        {:noreply,
         socket
         |> assign(:provider_test_result, %{status: :ok, content: result.content})
         |> put_flash(:info, "Provider test succeeded")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:provider_test_result, %{status: :error, content: inspect(reason)})
         |> put_flash(:error, "Provider test failed")}
    end
  end

  def handle_event("save_telegram", %{"telegram_config" => params}, socket) do
    params = Map.put_new(params, "default_agent_id", socket.assigns.agent.id)

    with {:ok, socket} <- require_recent_auth(socket, "save Telegram credentials"),
         {:ok, telegram} <- Runtime.save_telegram_config(socket.assigns.telegram, params) do
      {:noreply,
       socket
       |> put_flash(:info, "Telegram updated")
       |> assign(:telegram, telegram)
       |> assign(:readiness_report, Runtime.readiness_report())
       |> assign(:stats, stats())
       |> assign_form(:telegram_form, Runtime.change_telegram_config(telegram))}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, :telegram_form, changeset)}

      {:reauth, socket} ->
        {:noreply, socket}
    end
  end

  def handle_event("save_discord", %{"discord_config" => params}, socket) do
    params = Map.put_new(params, "default_agent_id", socket.assigns.agent.id)

    with {:ok, socket} <- require_recent_auth(socket, "save Discord credentials"),
         {:ok, discord} <- Runtime.save_discord_config(socket.assigns.discord, params) do
      {:noreply,
       socket
       |> put_flash(:info, "Discord updated")
       |> assign(:discord, discord)
       |> assign(:readiness_report, Runtime.readiness_report())
       |> assign(:stats, stats())
       |> assign_form(:discord_form, Runtime.change_discord_config(discord))}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, :discord_form, changeset)}

      {:reauth, socket} ->
        {:noreply, socket}
    end
  end

  def handle_event("save_slack", %{"slack_config" => params}, socket) do
    params = Map.put_new(params, "default_agent_id", socket.assigns.agent.id)

    with {:ok, socket} <- require_recent_auth(socket, "save Slack credentials"),
         {:ok, slack} <- Runtime.save_slack_config(socket.assigns.slack, params) do
      {:noreply,
       socket
       |> put_flash(:info, "Slack updated")
       |> assign(:slack, slack)
       |> assign(:readiness_report, Runtime.readiness_report())
       |> assign(:stats, stats())
       |> assign_form(:slack_form, Runtime.change_slack_config(slack))}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, :slack_form, changeset)}

      {:reauth, socket} ->
        {:noreply, socket}
    end
  end

  def handle_event("save_webchat", %{"webchat_config" => params}, socket) do
    params = Map.put_new(params, "default_agent_id", socket.assigns.agent.id)

    with {:ok, socket} <- require_recent_auth(socket, "save Webchat settings"),
         {:ok, webchat} <- Runtime.save_webchat_config(socket.assigns.webchat, params) do
      {:noreply,
       socket
       |> put_flash(:info, "Webchat updated")
       |> assign(:webchat, webchat)
       |> assign(:readiness_report, Runtime.readiness_report())
       |> assign(:stats, stats())
       |> assign_form(:webchat_form, Runtime.change_webchat_config(webchat))}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, :webchat_form, changeset)}

      {:reauth, socket} ->
        {:noreply, socket}
    end
  end

  def handle_event("save_tool_policy", %{"tool_policy" => params}, socket) do
    with {:ok, socket} <- require_recent_auth(socket, "save tool policy"),
         {:ok, tool_policy} <- Runtime.save_tool_policy(socket.assigns.tool_policy, params) do
      {:noreply,
       socket
       |> put_flash(:info, "Tool policy updated")
       |> assign(:tool_policy, tool_policy)
       |> assign(:readiness_report, Runtime.readiness_report())
       |> assign_form(:tool_policy_form, Runtime.change_tool_policy(tool_policy))}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, :tool_policy_form, changeset)}

      {:reauth, socket} ->
        {:noreply, socket}
    end
  end

  def handle_event("register_webhook", _params, socket) do
    case Runtime.register_telegram_webhook(socket.assigns.telegram) do
      {:ok, telegram} ->
        {:noreply,
         socket
         |> put_flash(:info, "Telegram webhook registered")
         |> assign(:telegram, telegram)
         |> assign(:readiness_report, Runtime.readiness_report())
         |> assign(:stats, stats())
         |> assign_form(:telegram_form, Runtime.change_telegram_config(telegram))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Webhook registration failed: #{inspect(reason)}")}
    end
  end

  def handle_event("sync_webhook", _params, socket) do
    case Runtime.sync_telegram_webhook_info(socket.assigns.telegram) do
      {:ok, telegram} ->
        {:noreply,
         socket
         |> put_flash(:info, "Telegram webhook status refreshed")
         |> assign(:telegram, telegram)
         |> assign(:readiness_report, Runtime.readiness_report())
         |> assign_form(:telegram_form, Runtime.change_telegram_config(telegram))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Webhook status refresh failed: #{inspect(reason)}")}
    end
  end

  def handle_event("delete_webhook", _params, socket) do
    case Runtime.delete_telegram_webhook(socket.assigns.telegram) do
      {:ok, telegram} ->
        {:noreply,
         socket
         |> put_flash(:info, "Telegram webhook removed")
         |> assign(:telegram, telegram)
         |> assign(:readiness_report, Runtime.readiness_report())
         |> assign_form(:telegram_form, Runtime.change_telegram_config(telegram))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Webhook removal failed: #{inspect(reason)}")}
    end
  end

  def handle_event("generate_telegram_secret", _params, socket) do
    secret = Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)
    changeset = Runtime.change_telegram_config(socket.assigns.telegram, %{webhook_secret: secret})

    {:noreply, assign_form(socket, :telegram_form, changeset)}
  end

  def handle_event("test_telegram_delivery", %{"telegram_test" => params}, socket) do
    case Runtime.test_telegram_delivery(
           socket.assigns.telegram,
           params["chat_id"],
           params["message"]
         ) do
      {:ok, result} ->
        {:noreply,
         socket
         |> assign(:telegram_test_result, %{status: :ok, content: inspect(result.metadata)})
         |> put_flash(:info, "Telegram delivery test succeeded")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:telegram_test_result, %{status: :error, content: inspect(reason)})
         |> put_flash(:error, "Telegram delivery test failed")}
    end
  end

  def handle_event("test_discord_delivery", %{"discord_test" => params}, socket) do
    case Runtime.test_discord_delivery(
           socket.assigns.discord,
           params["target"],
           params["message"]
         ) do
      {:ok, result} ->
        {:noreply,
         socket
         |> assign(:discord_test_result, %{status: :ok, content: inspect(result.metadata)})
         |> put_flash(:info, "Discord delivery test succeeded")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:discord_test_result, %{status: :error, content: inspect(reason)})
         |> put_flash(:error, "Discord delivery test failed")}
    end
  end

  def handle_event("test_slack_delivery", %{"slack_test" => params}, socket) do
    case Runtime.test_slack_delivery(
           socket.assigns.slack,
           params["target"],
           params["message"]
         ) do
      {:ok, result} ->
        {:noreply,
         socket
         |> assign(:slack_test_result, %{status: :ok, content: inspect(result.metadata)})
         |> put_flash(:info, "Slack delivery test succeeded")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:slack_test_result, %{status: :error, content: inspect(reason)})
         |> put_flash(:error, "Slack delivery test failed")}
    end
  end

  def handle_event("save_operator_password", %{"operator_secret" => params}, socket) do
    with {:ok, socket} <- require_recent_auth(socket, "rotate operator password"),
         {:ok, secret} <- Runtime.save_operator_secret_password(params) do
      {:noreply,
       socket
       |> put_flash(:info, "Operator password updated")
       |> assign(:operator_secret, secret)
       |> assign(:operator_status, Runtime.operator_status())
       |> assign(:operator_session, refresh_recent_auth(socket.assigns.operator_session))
       |> assign(:readiness_report, Runtime.readiness_report())
       |> assign_form(:operator_form, Runtime.change_operator_secret(secret))}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, :operator_form, changeset)}

      {:reauth, socket} ->
        {:noreply, socket}
    end
  end

  def handle_event("export_install", _params, socket) do
    with {:ok, socket} <- require_recent_auth(socket, "export install bundle") do
      {:ok, export} = HydraX.Install.export_snapshot()

      {:noreply,
       socket
       |> assign(:install_export, export)
       |> put_flash(:info, "Install bundle exported")}
    else
      {:reauth, socket} ->
        {:noreply, socket}
    end
  end

  def handle_event("create_backup_bundle", _params, socket) do
    with {:ok, socket} <- require_recent_auth(socket, "create backup bundle") do
      {:ok, manifest} = HydraX.Backup.create_bundle(HydraX.Config.backup_root())

      {:noreply,
       socket
       |> assign(:backup_export, manifest)
       |> assign(:readiness_report, Runtime.readiness_report())
       |> put_flash(:info, "Backup bundle created")}
    else
      {:reauth, socket} ->
        {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <AppShell.shell
      current={@current}
      stats={@stats}
      flash={@flash}
      operator_authenticated={@operator_authenticated}
    >
      <section class="mb-6">
        <article class="glass-panel p-6">
          <div class="text-xs uppercase tracking-[0.28em] text-[var(--hx-mute)]">
            Preview readiness
          </div>
          <h2 class="mt-3 font-display text-4xl">Install preflight</h2>
          <p class="mt-3 max-w-3xl text-sm text-[var(--hx-mute)]">
            Required items should be green before exposing the node publicly. Recommended items improve operator experience and recovery but do not block local boot.
          </p>
          <div class="mt-6 grid gap-3 lg:grid-cols-2">
            <article
              :for={item <- @readiness_report.items}
              class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4"
            >
              <div class="flex items-center justify-between gap-4">
                <div>
                  <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
                    {if item.required, do: "required", else: "recommended"}
                  </div>
                  <div class="mt-2 font-display text-2xl">{item.label}</div>
                </div>
                <span class={[
                  "rounded-full border px-3 py-1 font-mono text-xs uppercase tracking-[0.18em]",
                  if(item.status == :ok,
                    do: "border-emerald-400/20 bg-emerald-400/10 text-emerald-300",
                    else: "border-amber-400/20 bg-amber-400/10 text-amber-300"
                  )
                ]}>
                  {item.status}
                </span>
              </div>
              <p class="mt-3 text-sm text-[var(--hx-mute)]">{item.detail}</p>
            </article>
          </div>
        </article>
      </section>

      <section class="mb-6">
        <article class="glass-panel p-6">
          <div class="text-xs uppercase tracking-[0.28em] text-[var(--hx-mute)]">
            Deploy + recovery
          </div>
          <h2 class="mt-3 font-display text-4xl">Export runtime artifacts</h2>
          <p class="mt-3 max-w-3xl text-sm text-[var(--hx-mute)]">
            Generate deployment templates and portable backup bundles directly from the control plane.
          </p>
          <div class="mt-6 flex flex-wrap gap-3">
            <button
              type="button"
              phx-click="export_install"
              class="btn btn-outline border-white/10 bg-white/5 text-white hover:bg-white/10"
            >
              Export install bundle
            </button>
            <button
              type="button"
              phx-click="create_backup_bundle"
              class="btn btn-outline border-white/10 bg-white/5 text-white hover:bg-white/10"
            >
              Create backup bundle
            </button>
          </div>
          <div
            :if={@install_export}
            class="mt-4 rounded-2xl border border-white/10 bg-black/10 px-4 py-4 text-sm text-[var(--hx-mute)]"
          >
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-accent)]">
              Install export
            </div>
            <p class="mt-2 break-all">Env file: {@install_export.env_path}</p>
            <p class="mt-1 break-all">Preview note: {@install_export.note_path}</p>
          </div>
          <div
            :if={@backup_export}
            class="mt-4 rounded-2xl border border-white/10 bg-black/10 px-4 py-4 text-sm text-[var(--hx-mute)]"
          >
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-accent)]">
              Backup export
            </div>
            <p class="mt-2 break-all">Archive: {@backup_export["archive_path"]}</p>
            <p class="mt-1 break-all">Manifest: {@backup_export["manifest_path"]}</p>
          </div>
        </article>
      </section>

      <section class="mb-6">
        <article class="glass-panel p-6">
          <div class="text-xs uppercase tracking-[0.28em] text-[var(--hx-mute)]">
            Control plane auth
          </div>
          <h2 class="mt-3 font-display text-4xl">Operator password</h2>
          <p class="mt-3 max-w-3xl text-sm text-[var(--hx-mute)]">
            The management UI stays open until you set an operator password. After that, all browser routes require a signed session.
          </p>
          <div
            :if={@operator_secret}
            class="mt-4 rounded-2xl border border-white/10 bg-black/10 px-4 py-4 text-sm text-[var(--hx-mute)]"
          >
            Password active. Last rotated at {Calendar.strftime(
              @operator_secret.last_rotated_at,
              "%Y-%m-%d %H:%M:%S UTC"
            )}.
          </div>
          <div class="mt-4 rounded-2xl border border-white/10 bg-black/10 px-4 py-4 text-sm text-[var(--hx-mute)]">
            Sensitive actions require a fresh sign-in every {div(
              @operator_status.recent_auth_window_seconds,
              60
            )} minutes.
            Session max age is {div(@operator_status.session_max_age_seconds, 3600)} hours and idle timeout is {div(
              @operator_status.idle_timeout_seconds,
              60
            )} minutes.
            <span :if={@operator_status.password_age_days != nil}>
              Password age: {@operator_status.password_age_days} days.
            </span>
          </div>
          <.form
            for={@operator_form}
            id="operator-form"
            phx-submit="save_operator_password"
            class="mt-6 grid gap-4 xl:grid-cols-2"
          >
            <.input field={@operator_form[:password]} type="password" label="Password" />
            <.input
              field={@operator_form[:password_confirmation]}
              type="password"
              label="Confirm password"
            />
            <div class="xl:col-span-2 pt-2">
              <.button>Save operator password</.button>
            </div>
          </.form>
        </article>
      </section>

      <section class="grid gap-6 xl:grid-cols-2">
        <article class="glass-panel p-6">
          <div class="text-xs uppercase tracking-[0.28em] text-[var(--hx-mute)]">Agent bootstrap</div>
          <h2 class="mt-3 font-display text-4xl">Default operator identity</h2>
          <p class="mt-3 max-w-xl text-sm text-[var(--hx-mute)]">
            This agent is started on boot, owns the workspace scaffold, and serves as the default target for the CLI runtime.
          </p>
          <.form for={@agent_form} id="agent-form" phx-submit="save_agent" class="mt-6 space-y-2">
            <.input field={@agent_form[:name]} label="Name" />
            <.input field={@agent_form[:slug]} label="Slug" />
            <.input field={@agent_form[:workspace_root]} label="Workspace root" />
            <.input field={@agent_form[:description]} type="textarea" label="Description" />
            <.input field={@agent_form[:is_default]} type="checkbox" label="Default agent" />
            <div class="pt-2">
              <.button>Save agent</.button>
            </div>
          </.form>
        </article>

        <article class="glass-panel p-6">
          <div class="text-xs uppercase tracking-[0.28em] text-[var(--hx-mute)]">LLM routing</div>
          <h2 class="mt-3 font-display text-4xl">Primary provider</h2>
          <p class="mt-3 max-w-xl text-sm text-[var(--hx-mute)]">
            Leave this blank and Hydra-X will fall back to the built-in mock provider. Enable a real provider to test end-to-end model traffic.
          </p>
          <.form
            for={@provider_form}
            id="provider-form"
            phx-submit="save_provider"
            class="mt-6 space-y-2"
          >
            <.input field={@provider_form[:name]} label="Label" />
            <.input
              field={@provider_form[:kind]}
              type="select"
              label="Provider kind"
              options={[{"OpenAI compatible", "openai_compatible"}, {"Anthropic", "anthropic"}]}
            />
            <.input field={@provider_form[:model]} label="Model" />
            <.input field={@provider_form[:base_url]} label="Base URL" />
            <.input field={@provider_form[:api_key]} type="password" label="API key" />
            <.input
              field={@provider_form[:enabled]}
              type="checkbox"
              label="Enable as active provider"
            />
            <div
              :if={@provider_test_result}
              class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4 text-sm text-[var(--hx-mute)]"
            >
              {if @provider_test_result.status == :ok, do: "Test reply: ", else: "Failure: "}
              {@provider_test_result.content}
            </div>
            <div class="pt-2">
              <.button>Save provider</.button>
              <button
                type="button"
                phx-click="test_provider"
                class="btn btn-outline ml-3 border-white/10 bg-white/5 text-white hover:bg-white/10"
              >
                Test saved provider
              </button>
            </div>
          </.form>
        </article>
      </section>

      <section class="mt-6">
        <article class="glass-panel p-6">
          <div class="text-xs uppercase tracking-[0.28em] text-[var(--hx-mute)]">Tool policy</div>
          <h2 class="mt-3 font-display text-4xl">Guardrail defaults</h2>
          <p class="mt-3 max-w-3xl text-sm text-[var(--hx-mute)]">
            These settings define which guarded tools are available at runtime and which outbound hosts or shell commands are allowed by default.
          </p>
          <.form
            for={@tool_policy_form}
            id="tool-policy-form"
            phx-submit="save_tool_policy"
            class="mt-6 grid gap-4 xl:grid-cols-2"
          >
            <.input
              field={@tool_policy_form[:workspace_list_enabled]}
              type="checkbox"
              label="Enable workspace directory listing"
            />
            <.input
              field={@tool_policy_form[:workspace_read_enabled]}
              type="checkbox"
              label="Enable workspace file reads"
            />
            <.input
              field={@tool_policy_form[:workspace_write_enabled]}
              type="checkbox"
              label="Enable workspace file writes and patch edits"
            />
            <.input
              field={@tool_policy_form[:http_fetch_enabled]}
              type="checkbox"
              label="Enable outbound HTTP fetches"
            />
            <.input
              field={@tool_policy_form[:web_search_enabled]}
              type="checkbox"
              label="Enable dedicated web search"
            />
            <.input
              field={@tool_policy_form[:shell_command_enabled]}
              type="checkbox"
              label="Enable shell commands"
            />
            <.input
              field={@tool_policy_form[:shell_allowlist_csv]}
              label="Shell allowlist (comma separated)"
            />
            <.input
              field={@tool_policy_form[:http_allowlist_csv]}
              label="HTTP allowlist (comma separated, blank = public hosts)"
            />
            <.input
              field={@tool_policy_form[:workspace_write_channels_csv]}
              label="Workspace write channels (comma separated)"
            />
            <.input
              field={@tool_policy_form[:http_fetch_channels_csv]}
              label="HTTP fetch channels (comma separated)"
            />
            <.input
              field={@tool_policy_form[:web_search_channels_csv]}
              label="Web search channels (comma separated)"
            />
            <.input
              field={@tool_policy_form[:shell_command_channels_csv]}
              label="Shell channels (comma separated)"
            />
            <div class="xl:col-span-2 pt-2">
              <.button>Save tool policy</.button>
            </div>
          </.form>
        </article>
      </section>

      <section class="mt-6">
        <article class="glass-panel p-6">
          <div class="text-xs uppercase tracking-[0.28em] text-[var(--hx-mute)]">
            Telegram channel
          </div>
          <h2 class="mt-3 font-display text-4xl">Webhook ingress</h2>
          <p class="mt-3 max-w-3xl text-sm text-[var(--hx-mute)]">
            Configure a Telegram bot and point its webhook at <span class="font-mono text-[var(--hx-accent)]">/api/telegram/webhook</span>.
            Inbound messages are routed into the default agent and persisted as channel conversations.
          </p>
          <div class="mt-4 rounded-2xl border border-white/10 bg-black/10 px-4 py-4 text-sm text-[var(--hx-mute)]">
            <div>Webhook URL</div>
            <div class="mt-2 break-all font-mono text-xs text-[var(--hx-accent)]">
              {HydraX.Config.telegram_webhook_url()}
            </div>
            <div :if={@telegram.webhook_registered_at} class="mt-2 text-xs">
              Registered at {Calendar.strftime(
                @telegram.webhook_registered_at,
                "%Y-%m-%d %H:%M:%S UTC"
              )}
            </div>
            <div :if={@telegram.webhook_last_checked_at} class="mt-2 text-xs">
              Last checked at {Calendar.strftime(
                @telegram.webhook_last_checked_at,
                "%Y-%m-%d %H:%M:%S UTC"
              )}
            </div>
            <div class="mt-2 text-xs">
              Pending updates: {@telegram.webhook_pending_update_count || 0}
            </div>
            <div :if={@telegram.webhook_last_error} class="mt-2 text-xs text-amber-200">
              Last Telegram error: {@telegram.webhook_last_error}
            </div>
          </div>
          <.form
            for={@telegram_form}
            id="telegram-form"
            phx-submit="save_telegram"
            class="mt-6 grid gap-4 xl:grid-cols-2"
          >
            <.input field={@telegram_form[:bot_username]} label="Bot username" />
            <.input field={@telegram_form[:bot_token]} type="password" label="Bot token" />
            <.input field={@telegram_form[:webhook_secret]} label="Webhook secret (optional)" />
            <.input field={@telegram_form[:enabled]} type="checkbox" label="Enable Telegram ingress" />
            <div class="xl:col-span-2 pt-2">
              <.button>Save Telegram settings</.button>
              <button
                type="button"
                phx-click="generate_telegram_secret"
                class="btn btn-outline ml-3 border-white/10 bg-white/5 text-white hover:bg-white/10"
              >
                Generate secret
              </button>
              <button
                type="button"
                phx-click="register_webhook"
                class="btn btn-outline ml-3 border-white/10 bg-white/5 text-white hover:bg-white/10"
              >
                Register webhook
              </button>
              <button
                type="button"
                phx-click="sync_webhook"
                class="btn btn-outline ml-3 border-white/10 bg-white/5 text-white hover:bg-white/10"
              >
                Refresh status
              </button>
              <button
                type="button"
                phx-click="delete_webhook"
                class="btn btn-outline ml-3 border-white/10 bg-white/5 text-white hover:bg-white/10"
              >
                Remove webhook
              </button>
            </div>
          </.form>
          <.form
            for={@telegram_test_form}
            phx-submit="test_telegram_delivery"
            class="mt-6 grid gap-4 xl:grid-cols-[1fr_2fr_auto]"
          >
            <.input field={@telegram_test_form[:chat_id]} label="Test chat id" />
            <.input field={@telegram_test_form[:message]} label="Test message" />
            <div class="self-end pt-2">
              <.button>Send test delivery</.button>
            </div>
          </.form>
          <div
            :if={@telegram_test_result}
            class="mt-4 rounded-2xl border border-white/10 bg-black/10 px-4 py-4 text-sm text-[var(--hx-mute)]"
          >
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Telegram test result
            </div>
            <p class="mt-3 whitespace-pre-wrap">{@telegram_test_result.content}</p>
          </div>
        </article>
      </section>

      <section class="mt-6 grid gap-6 xl:grid-cols-2">
        <article class="glass-panel p-6">
          <div class="text-xs uppercase tracking-[0.28em] text-[var(--hx-mute)]">
            Discord channel
          </div>
          <h2 class="mt-3 font-display text-4xl">Webhook + outbound delivery</h2>
          <p class="mt-3 max-w-3xl text-sm text-[var(--hx-mute)]">
            Configure Discord so inbound interactions route into the default agent and outbound
            replies or scheduled jobs can be delivered back to a channel.
          </p>
          <.form
            for={@discord_form}
            id="discord-form"
            phx-submit="save_discord"
            class="mt-6 grid gap-4"
          >
            <.input field={@discord_form[:application_id]} label="Application ID" />
            <.input field={@discord_form[:bot_token]} type="password" label="Bot token" />
            <.input field={@discord_form[:webhook_secret]} label="Webhook secret (optional)" />
            <.input field={@discord_form[:enabled]} type="checkbox" label="Enable Discord ingress" />
            <div class="pt-2">
              <.button>Save Discord settings</.button>
            </div>
          </.form>
          <.form
            for={@discord_test_form}
            phx-submit="test_discord_delivery"
            class="mt-6 grid gap-4 xl:grid-cols-[1fr_2fr_auto]"
          >
            <.input field={@discord_test_form[:target]} label="Test channel id" />
            <.input field={@discord_test_form[:message]} label="Test message" />
            <div class="self-end pt-2">
              <.button>Send Discord test</.button>
            </div>
          </.form>
          <div
            :if={@discord_test_result}
            class="mt-4 rounded-2xl border border-white/10 bg-black/10 px-4 py-4 text-sm text-[var(--hx-mute)]"
          >
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Discord test result
            </div>
            <p class="mt-3 whitespace-pre-wrap">{@discord_test_result.content}</p>
          </div>
        </article>

        <article class="glass-panel p-6">
          <div class="text-xs uppercase tracking-[0.28em] text-[var(--hx-mute)]">
            Slack channel
          </div>
          <h2 class="mt-3 font-display text-4xl">Events API + outbound delivery</h2>
          <p class="mt-3 max-w-3xl text-sm text-[var(--hx-mute)]">
            Configure Slack event ingress and outbound delivery so replies and scheduled jobs can
            target a Slack channel without leaving the control plane.
          </p>
          <.form
            for={@slack_form}
            id="slack-form"
            phx-submit="save_slack"
            class="mt-6 grid gap-4"
          >
            <.input field={@slack_form[:bot_token]} type="password" label="Bot token" />
            <.input field={@slack_form[:signing_secret]} type="password" label="Signing secret" />
            <.input field={@slack_form[:enabled]} type="checkbox" label="Enable Slack ingress" />
            <div class="pt-2">
              <.button>Save Slack settings</.button>
            </div>
          </.form>
          <.form
            for={@slack_test_form}
            phx-submit="test_slack_delivery"
            class="mt-6 grid gap-4 xl:grid-cols-[1fr_2fr_auto]"
          >
            <.input field={@slack_test_form[:target]} label="Test channel id" />
            <.input field={@slack_test_form[:message]} label="Test message" />
            <div class="self-end pt-2">
              <.button>Send Slack test</.button>
            </div>
          </.form>
          <div
            :if={@slack_test_result}
            class="mt-4 rounded-2xl border border-white/10 bg-black/10 px-4 py-4 text-sm text-[var(--hx-mute)]"
          >
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-mute)]">
              Slack test result
            </div>
            <p class="mt-3 whitespace-pre-wrap">{@slack_test_result.content}</p>
          </div>
        </article>
      </section>

      <section class="mt-6">
        <article class="glass-panel p-6">
          <div class="text-xs uppercase tracking-[0.28em] text-[var(--hx-mute)]">
            Webchat channel
          </div>
          <h2 class="mt-3 font-display text-4xl">Public browser ingress</h2>
          <p class="mt-3 max-w-3xl text-sm text-[var(--hx-mute)]">
            Enable a session-backed browser channel at
            <span class="mx-1 font-mono text-[var(--hx-accent)]">/webchat</span>
            so visitors can chat with the default agent without going through Telegram, Discord,
            or Slack.
          </p>
          <div class="mt-4 rounded-2xl border border-white/10 bg-black/10 px-4 py-4 text-sm text-[var(--hx-mute)]">
            <div>Public route</div>
            <div class="mt-2 break-all font-mono text-xs text-[var(--hx-accent)]">
              /webchat
            </div>
            <div class="mt-2 text-xs">
              {if @webchat.enabled, do: "Webchat is enabled", else: "Webchat is disabled"}
              {if webchat_agent_name(@webchat),
                do: " -> #{webchat_agent_name(@webchat)}",
                else: ""}
            </div>
          </div>
          <.form
            for={@webchat_form}
            id="webchat-form"
            phx-submit="save_webchat"
            class="mt-6 grid gap-4 xl:grid-cols-2"
          >
            <.input field={@webchat_form[:title]} label="Title" />
            <.input field={@webchat_form[:subtitle]} label="Subtitle" />
            <.input
              field={@webchat_form[:composer_placeholder]}
              label="Composer placeholder"
            />
            <.input
              field={@webchat_form[:enabled]}
              type="checkbox"
              label="Enable public Webchat ingress"
            />
            <.input
              field={@webchat_form[:welcome_prompt]}
              type="textarea"
              label="Welcome prompt"
              class="xl:col-span-2"
            />
            <div class="xl:col-span-2 pt-2">
              <.button>Save Webchat settings</.button>
            </div>
          </.form>
        </article>
      </section>
    </AppShell.shell>
    """
  end

  defp assign_form(socket, key, changeset) do
    assign(socket, key, to_form(changeset))
  end

  defp stats do
    %{
      agents: Runtime.list_agents() |> length(),
      providers: Runtime.list_provider_configs() |> length(),
      turns:
        Runtime.list_conversations(limit: 200)
        |> Enum.flat_map(&Runtime.list_turns(&1.id))
        |> length(),
      memories: HydraX.Memory.list_memories(limit: 1_000) |> length()
    }
  end

  defp default_telegram_test do
    %{"chat_id" => "", "message" => "Hydra-X Telegram smoke test"}
  end

  defp webchat_agent_name(%{default_agent: %{name: name}}), do: name
  defp webchat_agent_name(_), do: nil

  defp default_channel_test(channel) do
    %{"target" => "", "message" => "Hydra-X #{String.capitalize(channel)} smoke test"}
  end

  defp require_recent_auth(socket, action) do
    cond do
      not Runtime.operator_password_configured?() ->
        {:ok, socket}

      socket.assigns.operator_session.recent_auth_valid? ->
        {:ok, socket}

      true ->
        Helpers.audit_auth_action("Blocked sensitive action pending re-authentication",
          level: "warn",
          agent: socket.assigns.agent,
          metadata: %{action: action}
        )

        {:reauth,
         socket
         |> put_flash(:error, "Sign in again to #{action}.")
         |> push_navigate(to: "/login?reauth=1")}
    end
  end

  defp refresh_recent_auth(session_state) do
    now = System.system_time(:second)

    session_state
    |> Map.put(:recent_auth_at, now)
    |> Map.put(:recent_auth_valid?, true)
    |> Map.put(
      :recent_auth_expires_at,
      DateTime.from_unix!(now + OperatorAuth.recent_auth_window_seconds())
    )
  end
end
