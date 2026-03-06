defmodule HydraXWeb.SetupLive do
  use HydraXWeb, :live_view

  alias HydraX.Runtime
  alias HydraX.Runtime.{AgentProfile, ProviderConfig}
  alias HydraXWeb.AppShell

  @impl true
  def mount(_params, _session, socket) do
    agent = Runtime.get_default_agent() || %AgentProfile{}

    provider =
      Runtime.enabled_provider() || List.first(Runtime.list_provider_configs()) ||
        %ProviderConfig{}

    {:ok,
     socket
     |> assign(:page_title, "Setup")
     |> assign(:current, "setup")
     |> assign(:stats, stats())
     |> assign(:agent, agent)
     |> assign(:provider, provider)
     |> assign_form(:agent_form, Runtime.change_agent(agent))
     |> assign_form(:provider_form, Runtime.change_provider_config(provider))}
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
         |> assign(:stats, stats())
         |> assign_form(:provider_form, Runtime.change_provider_config(provider))}

      {:error, changeset} ->
        {:noreply, assign_form(socket, :provider_form, changeset)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <AppShell.shell current={@current} stats={@stats} flash={@flash}>
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
            <div class="pt-2">
              <.button>Save provider</.button>
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
