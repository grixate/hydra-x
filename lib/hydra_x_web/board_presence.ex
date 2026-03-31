defmodule HydraXWeb.BoardPresence do
  use Phoenix.Presence, otp_app: :hydra_x, pubsub_server: HydraX.PubSub
end
