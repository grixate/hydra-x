defmodule HydraX.Repo do
  use Ecto.Repo,
    otp_app: :hydra_x,
    adapter: Ecto.Adapters.Postgres
end
