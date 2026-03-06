import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :hydra_x, HydraX.Repo,
  database: Path.expand("../hydra_x_test.db", __DIR__),
  busy_timeout: 15_000,
  journal_mode: :wal,
  pool_size: 1,
  pool: Ecto.Adapters.SQL.Sandbox

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :hydra_x, HydraXWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "CQ5LJnb7H2DdwBG7SwyLlaJsyvNJdr+fv97RlQCDb6r92BbqzeyU8bMucdqtOvZ7",
  server: false

# In test we don't send emails
config :hydra_x, HydraX.Mailer, adapter: Swoosh.Adapters.Test
config :hydra_x, :bootstrap_runtime, false

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

config :hydra_x, :sql_sandbox, true
