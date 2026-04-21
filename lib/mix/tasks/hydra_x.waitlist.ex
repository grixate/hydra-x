defmodule Mix.Tasks.HydraX.Waitlist do
  @moduledoc """
  Inspect and manage the Hydra waitlist (Stream A2.4).

  ## Usage

      mix hydra_x.waitlist list [--ungranted]
      mix hydra_x.waitlist grant <email>
      mix hydra_x.waitlist grant_bulk --since YYYY-MM-DD
      mix hydra_x.waitlist revoke <email>

  Examples:

      mix hydra_x.waitlist list
      mix hydra_x.waitlist list --ungranted
      mix hydra_x.waitlist grant alice@example.com
      mix hydra_x.waitlist grant_bulk --since 2026-04-01

  NOTE: This task does NOT send emails — that requires the email provider
  wiring from Stream A2.2, which is deferred. "Granting access" flips the
  `granted_at` column; the transactional email will be triggered once
  `HydraX.Mailer` has templates for `access_granted`.
  """

  use Mix.Task

  alias HydraX.Accounts
  alias HydraX.Repo

  @shortdoc "Manage the Hydra waitlist"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    case args do
      ["list" | rest] -> do_list(rest)
      ["grant", email] -> do_grant(email)
      ["grant_bulk" | rest] -> do_grant_bulk(rest)
      ["revoke", email] -> do_revoke(email)
      _ -> help()
    end
  end

  defp do_list(args) do
    only_ungranted = "--ungranted" in args
    entries = Accounts.list_waitlist(only_ungranted: only_ungranted, limit: 1000)

    if entries == [] do
      Mix.shell().info("(no entries)")
    else
      Mix.shell().info(String.pad_trailing("EMAIL", 32) <> " GRANTED  ADDED")

      Enum.each(entries, fn entry ->
        granted = if entry.granted_at, do: "✓", else: " "

        line =
          [
            String.pad_trailing(entry.email, 32),
            "   ",
            granted,
            "     ",
            format_ts(entry.inserted_at),
            if(entry.context, do: "  " <> String.slice(entry.context, 0, 40), else: "")
          ]
          |> IO.iodata_to_binary()

        Mix.shell().info(line)
      end)

      Mix.shell().info("\n#{length(entries)} entries")
    end
  end

  defp do_grant(email) do
    case Accounts.grant_waitlist_access(email, nil) do
      {:ok, entry} ->
        Mix.shell().info("✓ Granted access to #{entry.email} at #{entry.granted_at}")
        Mix.shell().info("(email send not wired — Stream A2.2)")

      {:error, :not_found} ->
        Mix.shell().error("No waitlist entry for #{email}")

      {:error, changeset} ->
        Mix.shell().error("Failed: #{inspect(changeset.errors)}")
    end
  end

  defp do_grant_bulk(args) do
    since =
      case parse_option(args, "--since") do
        nil ->
          Mix.shell().error("--since YYYY-MM-DD required for grant_bulk")
          exit({:shutdown, 1})

        date ->
          case Date.from_iso8601(date) do
            {:ok, d} -> DateTime.new!(d, ~T[00:00:00Z])
            _ -> Mix.raise("Invalid --since date: #{date}")
          end
      end

    import Ecto.Query

    entries =
      from(w in HydraX.Accounts.WaitlistEntry,
        where: is_nil(w.granted_at) and w.inserted_at >= ^since,
        order_by: [asc: w.inserted_at]
      )
      |> Repo.all()

    if entries == [] do
      Mix.shell().info("(no ungranted entries since #{DateTime.to_iso8601(since)})")
    else
      Mix.shell().info("Granting #{length(entries)} entries…")
      granted = Enum.count(entries, fn e -> match?({:ok, _}, do_grant_silent(e)) end)
      Mix.shell().info("✓ #{granted}/#{length(entries)} granted")
    end
  end

  defp do_grant_silent(entry) do
    Accounts.grant_waitlist_access(entry.email, nil)
  end

  defp do_revoke(email) do
    entry = Repo.get_by(HydraX.Accounts.WaitlistEntry, email: String.downcase(email))

    case entry do
      nil ->
        Mix.shell().error("No waitlist entry for #{email}")

      %{granted_at: nil} ->
        Mix.shell().info("Already not granted")

      _ ->
        entry
        |> Ecto.Changeset.change(granted_at: nil, granted_by_user_id: nil)
        |> Repo.update!()

        Mix.shell().info("Revoked #{email}")
    end
  end

  defp help do
    Mix.shell().info(@moduledoc)
  end

  defp parse_option([], _), do: nil
  defp parse_option([flag, value | _], flag), do: value
  defp parse_option([_ | rest], flag), do: parse_option(rest, flag)

  defp format_ts(nil), do: "(unset)"
  defp format_ts(dt), do: DateTime.to_date(dt) |> Date.to_iso8601()
end
