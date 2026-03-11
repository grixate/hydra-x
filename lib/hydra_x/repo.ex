defmodule HydraX.Repo do
  use Ecto.Repo,
    otp_app: :hydra_x,
    adapter: Application.compile_env(:hydra_x, :repo_adapter, Ecto.Adapters.SQLite3)
end
