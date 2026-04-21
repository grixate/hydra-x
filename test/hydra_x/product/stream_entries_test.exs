defmodule HydraX.Product.StreamEntriesTest do
  use HydraX.DataCase, async: false

  alias HydraX.Accounts
  alias HydraX.Product
  alias HydraX.Product.StreamEntries
  alias HydraX.Product.StreamEntry

  defp make_project!(name \\ "archive-test") do
    email = "stream+#{System.unique_integer([:positive])}@test.example.com"
    {:ok, %{user: _user, workspace: workspace}} =
      Accounts.create_user_with_workspace(%{"email" => email, "display_name" => "Tester"})

    {:ok, project, _onboarding} =
      Product.create_project(%{
        "name" => name,
        "description" => "t",
        "workspace_id" => workspace.id
      })

    project
  end

  describe "archive_stale/1" do
    test "deletes entries older than the cutoff and leaves fresh ones" do
      project = make_project!("archive 1")

      old_at = DateTime.utc_now() |> DateTime.add(-400 * 86_400, :second)
      fresh_at = DateTime.utc_now() |> DateTime.add(-30 * 86_400, :second)

      {:ok, old} =
        %StreamEntry{}
        |> StreamEntry.changeset(%{
          project_id: project.id,
          tab: "activity",
          title: "old"
        })
        |> Repo.insert()

      {:ok, fresh} =
        %StreamEntry{}
        |> StreamEntry.changeset(%{
          project_id: project.id,
          tab: "activity",
          title: "fresh"
        })
        |> Repo.insert()

      # Backdate via raw update because inserted_at is timestamped automatically.
      Repo.update_all(
        from(e in StreamEntry, where: e.id == ^old.id),
        set: [inserted_at: old_at]
      )

      Repo.update_all(
        from(e in StreamEntry, where: e.id == ^fresh.id),
        set: [inserted_at: fresh_at]
      )

      deleted = StreamEntries.archive_stale(365)

      assert deleted == 1
      assert Repo.get(StreamEntry, old.id) == nil
      assert Repo.get(StreamEntry, fresh.id) != nil
    end

    test "is a noop when no rows are stale" do
      _project = make_project!("archive 2")
      assert StreamEntries.archive_stale(365) == 0
    end
  end
end
