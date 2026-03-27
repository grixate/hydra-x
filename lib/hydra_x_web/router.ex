defmodule HydraXWeb.Router do
  use HydraXWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {HydraXWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :browser_authenticated do
    plug HydraXWeb.OperatorAuth, :require_authenticated_operator
  end

  pipeline :webchat_session do
    plug HydraXWeb.Plugs.WebchatSession
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :api_authenticated do
    plug :fetch_session
    plug HydraXWeb.Plugs.OperatorAPIAuth
  end

  scope "/", HydraXWeb do
    pipe_through :browser

    get "/login", SessionController, :new
    post "/login", SessionController, :create
    delete "/logout", SessionController, :delete
  end

  scope "/", HydraXWeb do
    pipe_through [:browser, :webchat_session]

    post "/webchat/session", WebchatSessionController, :create
    delete "/webchat/session", WebchatSessionController, :delete
    live "/webchat", WebchatLive
  end

  scope "/", HydraXWeb do
    pipe_through [:browser, :browser_authenticated]

    live_session :authenticated,
      on_mount: [{HydraXWeb.OperatorAuth, :require_authenticated_operator}] do
      live "/", HomeLive
      live "/setup", SetupLive
      live "/agents", AgentsLive
      live "/conversations", ConversationsLive
      live "/hx_conversations", ConversationsLive
      live "/memory", MemoryLive
      live "/jobs", JobsLive
      live "/budget", BudgetLive
      live "/safety", SafetyLive
      live "/settings/providers", ProviderSettingsLive
      live "/health", HealthLive
      live "/simulations", SimulationLive.Index, :index
      live "/simulations/new", SimulationLive.Configure, :new
      live "/simulations/:id", SimulationLive.Show, :show
      live "/simulations/:id/report", SimulationLive.Report, :report
    end
  end

  scope "/api", HydraXWeb do
    pipe_through :api

    post "/telegram/webhook", TelegramWebhookController, :create
    post "/discord/webhook", DiscordWebhookController, :create
    post "/slack/webhook", SlackWebhookController, :create
  end

  scope "/api/v1", HydraXWeb do
    pipe_through [:api, :api_authenticated]

    get "/projects", ProjectAPIController, :index
    post "/projects", ProjectAPIController, :create
    get "/projects/:id", ProjectAPIController, :show
    patch "/projects/:id", ProjectAPIController, :update
    delete "/projects/:id", ProjectAPIController, :delete
    get "/projects/:project_id/sources", SourceAPIController, :index
    post "/projects/:project_id/sources", SourceAPIController, :create
    get "/projects/:project_id/sources/:id", SourceAPIController, :show
    delete "/projects/:project_id/sources/:id", SourceAPIController, :delete
    get "/projects/:project_id/insights", InsightAPIController, :index
    post "/projects/:project_id/insights", InsightAPIController, :create
    get "/projects/:project_id/insights/:id", InsightAPIController, :show
    patch "/projects/:project_id/insights/:id", InsightAPIController, :update
    delete "/projects/:project_id/insights/:id", InsightAPIController, :delete
    get "/projects/:project_id/requirements", RequirementAPIController, :index
    post "/projects/:project_id/requirements", RequirementAPIController, :create
    get "/projects/:project_id/requirements/:id", RequirementAPIController, :show
    patch "/projects/:project_id/requirements/:id", RequirementAPIController, :update
    delete "/projects/:project_id/requirements/:id", RequirementAPIController, :delete
    get "/projects/:project_id/conversations", ProductConversationAPIController, :index
    post "/projects/:project_id/conversations", ProductConversationAPIController, :create
    get "/projects/:project_id/conversations/:id", ProductConversationAPIController, :show
    patch "/projects/:project_id/conversations/:id", ProductConversationAPIController, :update

    post "/projects/:project_id/conversations/:id/messages",
         ProductConversationAPIController,
         :create_message

    post "/projects/:project_id/exports", ProjectExportAPIController, :create
  end

  # Other scopes may use custom stacks.
  # scope "/api", HydraXWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:hydra_x, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: HydraXWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
