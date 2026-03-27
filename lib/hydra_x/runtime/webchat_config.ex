defmodule HydraX.Runtime.WebchatConfig do
  use Ecto.Schema
  import Ecto.Changeset

  schema "hx_webchat_configs" do
    field :title, :string, default: "Hydra-X Webchat"
    field :subtitle, :string, default: "A public channel into the operator runtime."
    field :welcome_prompt, :string
    field :composer_placeholder, :string, default: "Ask Hydra-X anything about this workspace..."
    field :enabled, :boolean, default: false
    field :allow_anonymous_messages, :boolean, default: true
    field :session_max_age_minutes, :integer, default: 24 * 60
    field :session_idle_timeout_minutes, :integer, default: 120
    field :attachments_enabled, :boolean, default: true
    field :max_attachment_count, :integer, default: 3
    field :max_attachment_size_kb, :integer, default: 2_048

    belongs_to :default_agent, HydraX.Runtime.AgentProfile

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(config, attrs) do
    config
    |> cast(attrs, [
      :title,
      :subtitle,
      :welcome_prompt,
      :composer_placeholder,
      :enabled,
      :allow_anonymous_messages,
      :session_max_age_minutes,
      :session_idle_timeout_minutes,
      :attachments_enabled,
      :max_attachment_count,
      :max_attachment_size_kb,
      :default_agent_id
    ])
    |> validate_required([:title])
    |> validate_number(:session_max_age_minutes, greater_than: 0, less_than_or_equal_to: 10_080)
    |> validate_number(:session_idle_timeout_minutes,
      greater_than: 0,
      less_than_or_equal_to: 1_440
    )
    |> validate_number(:max_attachment_count,
      greater_than_or_equal_to: 1,
      less_than_or_equal_to: 10
    )
    |> validate_number(:max_attachment_size_kb, greater_than: 0, less_than_or_equal_to: 10_240)
    |> assoc_constraint(:default_agent)
  end
end
