defmodule HydraXWeb.SetupLive do
  use HydraXWeb, :live_view

  alias HydraX.Runtime
  alias HydraX.Runtime.{AgentProfile, ProviderConfig, TelegramConfig, ToolPolicy}
  alias HydraXWeb.AppShell

  @impl true
  def mount(_params, _session, socket) do
    agent = Runtime.get_default_agent() || %AgentProfile{}

    provider =
      Runtime.enabled_provider() || List.first(Runtime.list_provider_configs()) ||
        %ProviderConfig{}

    telegram =
      Runtime.enabled_telegram_config() || List.first(Runtime.list_telegram_configs()) ||
        %TelegramConfig{default_agent_id: agent.id}

    tool_policy = Runtime.get_tool_policy() || %ToolPolicy{}

    {:ok,
     socket
     |> assign(:page_title, "Setup")
     |> assign(:current, "setup")
     |> assign(:operator_secret, Runtime.get_operator_secret())
     |> assign(:provider_test_result, nil)
     |> assign(:install_export, nil)
     |> assign(:backup_export, nil)
     |> assign(:readiness_report, Runtime.readiness_report())
     |> assign(:stats, stats())
     |> assign(:agent, agent)
     |> assign(:provider, provider)
     |> assign(:telegram, telegram)
     |> assign(:tool_policy, tool_policy)
     |> assign_form(:operator_form, Runtime.change_operator_secret())
     |> assign_form(:agent_form, Runtime.change_agent(agent))
     |> assign_form(:provider_form, Runtime.change_provider_config(provider))
     |> assign_form(:telegram_form, Runtime.change_telegram_config(telegram))
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
    case Runtime.save_provider_config(socket.assigns.provider, params) do
      {:ok, provider} ->
        {:noreply,
         socket
         |> put_flash(:info, "Provider updated")
         |> assign(:provider, provider)
         |> assign(:readiness_report, Runtime.readiness_report())
         |> assign(:stats, stats())
         |> assign_form(:provider_form, Runtime.change_provider_config(provider))}

      {:error, changeset} ->
        {:noreply, assign_form(socket, :provider_form, changeset)}
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

    case Runtime.save_telegram_config(socket.assigns.telegram, params) do
      {:ok, telegram} ->
        {:noreply,
         socket
         |> put_flash(:info, "Telegram updated")
         |> assign(:telegram, telegram)
         |> assign(:readiness_report, Runtime.readiness_report())
         |> assign(:stats, stats())
         |> assign_form(:telegram_form, Runtime.change_telegram_config(telegram))}

      {:error, changeset} ->
        {:noreply, assign_form(socket, :telegram_form, changeset)}
    end
  end

  def handle_event("save_tool_policy", %{"tool_policy" => params}, socket) do
    case Runtime.save_tool_policy(socket.assigns.tool_policy, params) do
      {:ok, tool_policy} ->
        {:noreply,
         socket
         |> put_flash(:info, "Tool policy updated")
         |> assign(:tool_policy, tool_policy)
         |> assign(:readiness_report, Runtime.readiness_report())
         |> assign_form(:tool_policy_form, Runtime.change_tool_policy(tool_policy))}

      {:error, changeset} ->
        {:noreply, assign_form(socket, :tool_policy_form, changeset)}
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

  def handle_event("save_operator_password", %{"operator_secret" => params}, socket) do
    case Runtime.save_operator_secret_password(params) do
      {:ok, secret} ->
        {:noreply,
         socket
         |> put_flash(:info, "Operator password updated")
         |> assign(:operator_secret, secret)
         |> assign(:readiness_report, Runtime.readiness_report())
         |> assign_form(:operator_form, Runtime.change_operator_secret(secret))}

      {:error, changeset} ->
        {:noreply, assign_form(socket, :operator_form, changeset)}
    end
  end

  def handle_event("export_install", _params, socket) do
    {:ok, export} = HydraX.Install.export_snapshot()

    {:noreply,
     socket
     |> assign(:install_export, export)
     |> put_flash(:info, "Install bundle exported")}
  end

  def handle_event("create_backup_bundle", _params, socket) do
    {:ok, manifest} = HydraX.Backup.create_bundle(HydraX.Config.backup_root())

    {:noreply,
     socket
     |> assign(:backup_export, manifest)
     |> assign(:readiness_report, Runtime.readiness_report())
     |> put_flash(:info, "Backup bundle created")}
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
              field={@tool_policy_form[:workspace_read_enabled]}
              type="checkbox"
              label="Enable workspace file reads"
            />
            <.input
              field={@tool_policy_form[:http_fetch_enabled]}
              type="checkbox"
              label="Enable outbound HTTP fetches"
            />
            <.input
              field={@tool_policy_form[:shell_command_enabled]}
              type="checkbox"
              label="Enable shell commands"
            />
            <div></div>
            <.input
              field={@tool_policy_form[:shell_allowlist_csv]}
              label="Shell allowlist (comma separated)"
            />
            <.input
              field={@tool_policy_form[:http_allowlist_csv]}
              label="HTTP allowlist (comma separated, blank = public hosts)"
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
end
