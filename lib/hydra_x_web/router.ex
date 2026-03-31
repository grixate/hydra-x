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

    get "/product", PageController, :product
    get "/product/*path", PageController, :product
    get "/projects", PageController, :product
    get "/projects/*path", PageController, :product
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

      # Product surfaces
      live "/projects/:project_id/stream", StreamLive
      live "/projects/:project_id/graph", GraphLive
      live "/projects/:project_id/board", BoardLive.Index, :index
      live "/projects/:project_id/board/:id", BoardLive.Show, :show
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

    # Watch targets (Continuous Research)
    get "/projects/:project_id/watch_targets", WatchTargetAPIController, :index
    post "/projects/:project_id/watch_targets", WatchTargetAPIController, :create
    delete "/projects/:project_id/watch_targets/:id", WatchTargetAPIController, :delete

    # Product simulations
    get "/projects/:project_id/simulations", SimulationAPIController, :index
    post "/projects/:project_id/simulations", SimulationAPIController, :create
    get "/projects/:project_id/simulations/:id", SimulationAPIController, :show
    post "/projects/:project_id/simulations/:id/import", SimulationAPIController, :import_results

    # Stream
    get "/projects/:project_id/stream", StreamAPIController, :index

    # Graph visualization
    get "/projects/:project_id/graph/nodes", GraphNodesAPIController, :index
    get "/projects/:project_id/graph/data", GraphDataAPIController, :show
    get "/projects/:project_id/graph/trail", GraphTrailAPIController, :show
    post "/projects/:project_id/graph/edges", GraphEdgeAPIController, :create
    get "/projects/:project_id/graph/edges/:id", GraphEdgeAPIController, :show
    delete "/projects/:project_id/graph/edges/:id", GraphEdgeAPIController, :delete

    # Decisions CRUD
    get "/projects/:project_id/decisions", DecisionAPIController, :index
    post "/projects/:project_id/decisions", DecisionAPIController, :create
    get "/projects/:project_id/decisions/:id", DecisionAPIController, :show
    patch "/projects/:project_id/decisions/:id", DecisionAPIController, :update
    delete "/projects/:project_id/decisions/:id", DecisionAPIController, :delete

    # Strategies CRUD
    get "/projects/:project_id/strategies", StrategyAPIController, :index
    post "/projects/:project_id/strategies", StrategyAPIController, :create
    get "/projects/:project_id/strategies/:id", StrategyAPIController, :show
    patch "/projects/:project_id/strategies/:id", StrategyAPIController, :update
    delete "/projects/:project_id/strategies/:id", StrategyAPIController, :delete

    # Design nodes CRUD
    get "/projects/:project_id/design_nodes", DesignNodeAPIController, :index
    post "/projects/:project_id/design_nodes", DesignNodeAPIController, :create
    get "/projects/:project_id/design_nodes/:id", DesignNodeAPIController, :show
    patch "/projects/:project_id/design_nodes/:id", DesignNodeAPIController, :update
    delete "/projects/:project_id/design_nodes/:id", DesignNodeAPIController, :delete

    # Architecture nodes CRUD
    get "/projects/:project_id/architecture_nodes", ArchitectureNodeAPIController, :index
    post "/projects/:project_id/architecture_nodes", ArchitectureNodeAPIController, :create
    get "/projects/:project_id/architecture_nodes/:id", ArchitectureNodeAPIController, :show
    patch "/projects/:project_id/architecture_nodes/:id", ArchitectureNodeAPIController, :update
    delete "/projects/:project_id/architecture_nodes/:id", ArchitectureNodeAPIController, :delete

    # Tasks CRUD
    get "/projects/:project_id/tasks", TaskAPIController, :index
    post "/projects/:project_id/tasks", TaskAPIController, :create
    get "/projects/:project_id/tasks/:id", TaskAPIController, :show
    patch "/projects/:project_id/tasks/:id", TaskAPIController, :update
    delete "/projects/:project_id/tasks/:id", TaskAPIController, :delete

    # Learnings CRUD
    get "/projects/:project_id/learnings", LearningAPIController, :index
    post "/projects/:project_id/learnings", LearningAPIController, :create
    get "/projects/:project_id/learnings/:id", LearningAPIController, :show
    patch "/projects/:project_id/learnings/:id", LearningAPIController, :update
    delete "/projects/:project_id/learnings/:id", LearningAPIController, :delete

    # Graph flags and health
    get "/projects/:project_id/graph/flags", GraphFlagAPIController, :index
    post "/projects/:project_id/graph/flags/:id/resolve", GraphFlagAPIController, :resolve
    get "/projects/:project_id/graph/health", GraphHealthAPIController, :show

    # Project counts (extended)
    get "/projects/:project_id/counts", ProjectAPIController, :counts

    # Constraints
    get "/projects/:project_id/constraints", ConstraintAPIController, :index
    post "/projects/:project_id/constraints", ConstraintAPIController, :create
    get "/projects/:project_id/constraints/:id", ConstraintAPIController, :show
    patch "/projects/:project_id/constraints/:id", ConstraintAPIController, :update
    delete "/projects/:project_id/constraints/:id", ConstraintAPIController, :delete

    # Routines
    get "/projects/:project_id/routines", RoutineAPIController, :index
    post "/projects/:project_id/routines", RoutineAPIController, :create
    get "/projects/:project_id/routines/:id", RoutineAPIController, :show
    patch "/projects/:project_id/routines/:id", RoutineAPIController, :update
    delete "/projects/:project_id/routines/:id", RoutineAPIController, :delete
    post "/projects/:project_id/routines/:id/run", RoutineAPIController, :run
    get "/projects/:project_id/routines/:id/runs", RoutineAPIController, :runs

    # Knowledge entries
    get "/projects/:project_id/knowledge", KnowledgeEntryAPIController, :index
    post "/projects/:project_id/knowledge", KnowledgeEntryAPIController, :create
    get "/projects/:project_id/knowledge/:id", KnowledgeEntryAPIController, :show
    patch "/projects/:project_id/knowledge/:id", KnowledgeEntryAPIController, :update
    delete "/projects/:project_id/knowledge/:id", KnowledgeEntryAPIController, :delete

    # Task feedback
    get "/projects/:project_id/tasks/:task_id/feedback", TaskFeedbackAPIController, :index
    post "/projects/:project_id/tasks/:task_id/feedback", TaskFeedbackAPIController, :create

    # My Work
    get "/projects/:project_id/my-work", MyWorkAPIController, :index
    get "/projects/:project_id/agents/:agent_slug/work", AgentWorkAPIController, :show

    # Board sessions
    get "/projects/:project_id/board_sessions", BoardSessionAPIController, :index
    post "/projects/:project_id/board_sessions", BoardSessionAPIController, :create
    get "/projects/:project_id/board_sessions/:id", BoardSessionAPIController, :show
    patch "/projects/:project_id/board_sessions/:id", BoardSessionAPIController, :update
    delete "/projects/:project_id/board_sessions/:id", BoardSessionAPIController, :delete

    # Board nodes (nested under sessions)
    get "/projects/:project_id/board_sessions/:session_id/nodes", BoardNodeAPIController, :index

    post "/projects/:project_id/board_sessions/:session_id/nodes",
         BoardNodeAPIController,
         :create

    get "/projects/:project_id/board_sessions/:session_id/nodes/:id",
        BoardNodeAPIController,
        :show

    patch "/projects/:project_id/board_sessions/:session_id/nodes/:id",
          BoardNodeAPIController,
          :update

    delete "/projects/:project_id/board_sessions/:session_id/nodes/:id",
           BoardNodeAPIController,
           :delete

    post "/projects/:project_id/board_sessions/:session_id/nodes/:id/promote",
         BoardNodeAPIController,
         :promote

    post "/projects/:project_id/board_sessions/:session_id/nodes/:id/react",
         BoardNodeAPIController,
         :react

    post "/projects/:project_id/board_sessions/:session_id/nodes/promote_batch",
         BoardNodeAPIController,
         :promote_batch

    # Board edges
    post "/projects/:project_id/board_sessions/:session_id/edges",
         BoardEdgeAPIController,
         :create

    delete "/projects/:project_id/board_sessions/:session_id/edges/:id",
           BoardEdgeAPIController,
           :delete
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
