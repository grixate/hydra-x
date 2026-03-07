defmodule Mix.Tasks.HydraX.Safety do
  use Mix.Task

  @shortdoc "Lists recent safety events with optional filters"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _positional, _invalid} =
      OptionParser.parse(args,
        strict: [
          level: :string,
          category: :string,
          status: :string,
          limit: :integer,
          note: :string
        ]
      )

    case args do
      ["acknowledge", id | _] ->
        event = HydraX.Safety.acknowledge_event!(String.to_integer(id), "cli", opts[:note])
        Mix.shell().info("acknowledged=#{event.id}")

      ["resolve", id | _] ->
        event = HydraX.Safety.resolve_event!(String.to_integer(id), "cli", opts[:note])
        Mix.shell().info("resolved=#{event.id}")

      ["reopen", id | _] ->
        event = HydraX.Safety.reopen_event!(String.to_integer(id), "cli", opts[:note])
        Mix.shell().info("reopened=#{event.id}")

      _ ->
        events =
          HydraX.Safety.list_events(
            level: opts[:level],
            category: opts[:category],
            status: opts[:status],
            limit: opts[:limit] || 25
          )

        Enum.each(events, fn event ->
          Mix.shell().info(
            Enum.join(
              [
                Calendar.strftime(event.inserted_at, "%Y-%m-%d %H:%M UTC"),
                event.level,
                event.status,
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
end
