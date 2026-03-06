defmodule Mix.Tasks.HydraX.Conversations do
  use Mix.Task

  @shortdoc "Lists conversations or retries failed Telegram deliveries"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    case args do
      ["retry-delivery", id] ->
        conversation = HydraX.Runtime.get_conversation!(String.to_integer(id))

        case HydraX.Gateway.retry_conversation_delivery(conversation) do
          {:ok, updated} ->
            Mix.shell().info(
              "Retried #{updated.metadata["last_delivery"]["channel"]} delivery for conversation #{updated.id}"
            )

          {:error, reason} ->
            Mix.raise("retry failed: #{inspect(reason)}")
        end

      _ ->
        HydraX.Runtime.list_conversations(limit: 25)
        |> Enum.each(fn conversation ->
          delivery =
            case conversation.metadata do
              %{"last_delivery" => %{"status" => status, "channel" => channel}} ->
                "#{channel}:#{status}"

              _ ->
                "-"
            end

          Mix.shell().info(
            Enum.join(
              [
                to_string(conversation.id),
                conversation.channel,
                conversation.title || "Untitled",
                delivery
              ],
              "\t"
            )
          )
        end)
    end
  end
end
