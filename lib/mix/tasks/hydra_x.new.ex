defmodule Mix.Tasks.HydraX.New do
  use Mix.Task

  @shortdoc "Scaffolds a Hydra-X workspace contract"

  @impl true
  def run(args) do
    {opts, positional, _invalid} =
      OptionParser.parse(args, strict: [name: :string, slug: :string])

    path = List.first(positional) || "./workspace"
    slug = opts[:slug] || slugify(opts[:name] || Path.basename(path))
    destination = Path.expand(path, File.cwd!())

    HydraX.Workspace.Scaffold.copy_template!(destination)

    Mix.shell().info("Hydra-X workspace scaffolded at #{destination} for #{slug}")
  end

  defp slugify(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end
end
