defmodule Mix.Tasks.HydraX.Serve do
  use Mix.Task

  @shortdoc "Starts the Hydra-X Phoenix server"

  @impl true
  def run(args) do
    Application.put_env(
      :hydra_x,
      HydraXWeb.Endpoint,
      Keyword.put(Application.get_env(:hydra_x, HydraXWeb.Endpoint, []), :server, true)
    )

    Mix.Tasks.Phx.Server.run(args)
  end
end
