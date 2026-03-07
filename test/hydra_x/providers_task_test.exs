defmodule HydraX.ProvidersTaskTest do
  use HydraX.DataCase

  import ExUnit.CaptureIO

  alias HydraX.Runtime

  test "providers task can activate and delete providers" do
    Mix.Task.reenable("hydra_x.providers")

    {:ok, first} =
      Runtime.save_provider_config(%{
        name: "First Provider",
        kind: "openai_compatible",
        base_url: "https://first.test",
        api_key: "secret",
        model: "gpt-first",
        enabled: false
      })

    {:ok, second} =
      Runtime.save_provider_config(%{
        name: "Second Provider",
        kind: "openai_compatible",
        base_url: "https://second.test",
        api_key: "secret",
        model: "gpt-second",
        enabled: false
      })

    activate_output =
      capture_io(fn ->
        Mix.Tasks.HydraX.Providers.run(["activate", to_string(second.id)])
      end)

    assert activate_output =~ "active=Second Provider"
    assert Runtime.enabled_provider().id == second.id

    Mix.Task.reenable("hydra_x.providers")

    delete_output =
      capture_io(fn ->
        Mix.Tasks.HydraX.Providers.run(["delete", to_string(first.id)])
      end)

    assert delete_output =~ "deleted=First Provider"
    assert_raise Ecto.NoResultsError, fn -> Runtime.get_provider_config!(first.id) end
  end
end
