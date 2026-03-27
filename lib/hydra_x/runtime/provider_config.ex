defmodule HydraX.Runtime.ProviderConfig do
  use Ecto.Schema
  import Ecto.Changeset

  @kinds ~w(openai_compatible anthropic)

  schema "hx_provider_configs" do
    field :name, :string
    field :kind, :string
    field :base_url, :string
    field :api_key, :string
    field :model, :string
    field :enabled, :boolean, default: false
    field :config, :map, default: %{}

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(provider, attrs) do
    provider
    |> cast(attrs, [:name, :kind, :base_url, :api_key, :model, :enabled, :config])
    |> validate_required([:name, :kind, :model])
    |> validate_inclusion(:kind, @kinds)
    |> validate_change(:base_url, fn :base_url, value ->
      if is_nil(value) or value == "" or String.starts_with?(value, ["http://", "https://"]) do
        []
      else
        [base_url: "must be an http or https URL"]
      end
    end)
  end
end
