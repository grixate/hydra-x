defmodule HydraX.CoordinationTest do
  use HydraX.DataCase

  alias HydraX.Runtime

  test "coordination status defaults to database leases on postgres" do
    status = Runtime.coordination_status()

    assert status.mode == "database_leases"
    assert status.backend == "postgres"
    assert status.enabled
  end

  test "leases can be claimed renewed and reassigned after expiry" do
    previous_adapter = Application.get_env(:hydra_x, :repo_adapter)

    Application.put_env(:hydra_x, :repo_adapter, Ecto.Adapters.Postgres)

    on_exit(fn ->
      if previous_adapter do
        Application.put_env(:hydra_x, :repo_adapter, previous_adapter)
      else
        Application.delete_env(:hydra_x, :repo_adapter)
      end
    end)

    assert {:ok, lease} =
             Runtime.claim_lease("scheduler:poller",
               owner: "node:a",
               ttl_seconds: 60,
               metadata: %{"role" => "scheduler"}
             )

    assert lease.owner == "node:a"
    assert Runtime.coordination_status().mode == "database_leases"

    assert {:error, {:taken, taken_lease}} =
             Runtime.claim_lease("scheduler:poller", owner: "node:b", ttl_seconds: 60)

    assert taken_lease.owner == "node:a"

    assert {:ok, renewed} =
             Runtime.claim_lease("scheduler:poller", owner: "node:a", ttl_seconds: 120)

    assert renewed.owner == "node:a"

    expired =
      renewed
      |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(), -60, :second))
      |> HydraX.Repo.update!()

    assert expired.owner == "node:a"

    assert {:ok, reassigned} =
             Runtime.claim_lease("scheduler:poller", owner: "node:b", ttl_seconds: 60)

    assert reassigned.owner == "node:b"
    assert :ok = Runtime.release_lease("scheduler:poller", owner: "node:b")
    assert Runtime.active_lease("scheduler:poller") == nil
  end
end
