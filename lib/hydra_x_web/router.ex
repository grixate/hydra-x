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

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", HydraXWeb do
    pipe_through :browser

    get "/login", SessionController, :new
    post "/login", SessionController, :create
    delete "/logout", SessionController, :delete
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
      live "/memory", MemoryLive
      live "/jobs", JobsLive
      live "/budget", BudgetLive
      live "/safety", SafetyLive
      live "/settings/providers", ProviderSettingsLive
      live "/health", HealthLive
    end
  end

  scope "/api", HydraXWeb do
    pipe_through :api

    post "/telegram/webhook", TelegramWebhookController, :create
    post "/discord/webhook", DiscordWebhookController, :create
    post "/slack/webhook", SlackWebhookController, :create
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
