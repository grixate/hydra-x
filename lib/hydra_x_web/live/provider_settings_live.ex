defmodule HydraXWeb.ProviderSettingsLive do
  use HydraXWeb, :live_view

  alias HydraX.Runtime
  alias HydraX.Runtime.ProviderConfig
  alias HydraXWeb.AppShell

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Providers")
     |> assign(:current, "providers")
     |> assign(:stats, stats())
     |> assign(:providers, Runtime.list_provider_configs())
     |> assign(:test_result, nil)
     |> assign(:form, to_form(Runtime.change_provider_config(%ProviderConfig{})))}
  end

  @impl true
  def handle_event("create", %{"provider_config" => params}, socket) do
    case Runtime.save_provider_config(params) do
      {:ok, _provider} ->
        {:noreply,
         socket
         |> put_flash(:info, "Provider saved")
         |> assign(:providers, Runtime.list_provider_configs())
         |> assign(:stats, stats())
         |> assign(:form, to_form(Runtime.change_provider_config(%ProviderConfig{})))}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("test", %{"id" => id}, socket) do
    provider = Runtime.get_provider_config!(id)

    case Runtime.test_provider_config(provider) do
      {:ok, result} ->
        {:noreply,
         socket
         |> assign(:test_result, %{provider: provider.name, status: :ok, content: result.content})
         |> put_flash(:info, "Provider test succeeded")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:test_result, %{
           provider: provider.name,
           status: :error,
           content: inspect(reason)
         })
         |> put_flash(:error, "Provider test failed")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <AppShell.shell current={@current} stats={@stats} flash={@flash}>
      <section class="grid gap-6 xl:grid-cols-[1.1fr_0.9fr]">
        <article class="glass-panel p-6">
          <div class="text-xs uppercase tracking-[0.28em] text-[var(--hx-mute)]">
            Configured providers
          </div>
          <div class="mt-4 space-y-3">
            <div
              :for={provider <- @providers}
              class="rounded-2xl border border-white/10 bg-black/10 px-4 py-4"
            >
              <div class="flex items-center justify-between gap-4">
                <div>
                  <div class="font-display text-2xl">{provider.name}</div>
                  <div class="mt-1 text-sm text-[var(--hx-mute)]">
                    {provider.kind} · {provider.model}
                  </div>
                </div>
                <span class={[
                  "rounded-full border px-3 py-1 font-mono text-xs uppercase tracking-[0.18em]",
                  if(provider.enabled,
                    do: "border-emerald-400/20 bg-emerald-400/10 text-emerald-300",
                    else: "border-white/10 text-[var(--hx-mute)]"
                  )
                ]}>
                  {if(provider.enabled, do: "active", else: "standby")}
                </span>
              </div>
              <div class="mt-3 break-all text-sm text-[var(--hx-mute)]">
                {provider.base_url || "default endpoint"}
              </div>
              <button
                type="button"
                phx-click="test"
                phx-value-id={provider.id}
                class="btn btn-outline mt-4 border-white/10 bg-white/5 text-white hover:bg-white/10"
              >
                Test provider
              </button>
            </div>
          </div>
        </article>

        <article class="glass-panel p-6">
          <div class="text-xs uppercase tracking-[0.28em] text-[var(--hx-mute)]">Add provider</div>
          <div
            :if={@test_result}
            class="mt-4 rounded-2xl border border-white/10 bg-black/10 px-4 py-4 text-sm text-[var(--hx-mute)]"
          >
            <div class="font-mono text-xs uppercase tracking-[0.18em] text-[var(--hx-accent)]">
              {@test_result.provider}
            </div>
            <p class="mt-2">
              {if @test_result.status == :ok, do: "Test reply: ", else: "Failure: "}
              {@test_result.content}
            </p>
          </div>
          <.form for={@form} phx-submit="create" class="mt-6 space-y-2">
            <.input field={@form[:name]} label="Label" />
            <.input
              field={@form[:kind]}
              type="select"
              label="Kind"
              options={[{"OpenAI compatible", "openai_compatible"}, {"Anthropic", "anthropic"}]}
            />
            <.input field={@form[:model]} label="Model" />
            <.input field={@form[:base_url]} label="Base URL" />
            <.input field={@form[:api_key]} type="password" label="API key" />
            <.input field={@form[:enabled]} type="checkbox" label="Set active" />
            <div class="pt-2">
              <.button>Save provider</.button>
            </div>
          </.form>
        </article>
      </section>
    </AppShell.shell>
    """
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
