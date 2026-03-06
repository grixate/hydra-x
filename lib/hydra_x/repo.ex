defmodule HydraX.Repo do
  use Ecto.Repo,
    otp_app: :hydra_x,
    adapter: Ecto.Adapters.SQLite3
end
