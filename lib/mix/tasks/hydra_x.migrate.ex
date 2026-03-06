defmodule Mix.Tasks.HydraX.Migrate do
  use Mix.Task

  @shortdoc "Creates and migrates the Hydra-X database"

  @impl true
  def run(_args) do
    Mix.Task.run("ecto.create", [])
    Mix.Task.run("ecto.migrate", [])
  end
end
