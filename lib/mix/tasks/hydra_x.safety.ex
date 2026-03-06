defmodule Mix.Tasks.HydraX.Safety do
  use Mix.Task

  @shortdoc "Lists recent safety events with optional filters"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _positional, _invalid} =
      OptionParser.parse(args, strict: [level: :string, category: :string, limit: :integer])

    events =
      HydraX.Safety.list_events(
        level: opts[:level],
        category: opts[:category],
        limit: opts[:limit] || 25
      )

    Enum.each(events, fn event ->
      Mix.shell().info(
        Enum.join(
          [
            Calendar.strftime(event.inserted_at, "%Y-%m-%d %H:%M UTC"),
            event.level,
            event.category,
            (event.agent && event.agent.name) || "-",
            event.message
          ],
          "\t"
        )
      )
    end)
  end
end
