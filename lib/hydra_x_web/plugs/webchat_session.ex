defmodule HydraXWeb.Plugs.WebchatSession do
  @moduledoc false

  import Plug.Conn

  alias HydraX.Runtime

  @session_id_key :webchat_session_id
  @session_created_at_key :webchat_session_created_at
  @session_last_active_at_key :webchat_session_last_active_at
  @display_name_key :webchat_display_name
  @reset_reason_key :webchat_session_reset_reason

  def init(opts), do: opts

  def call(conn, _opts) do
    config =
      Runtime.enabled_webchat_config() || List.first(Runtime.list_webchat_configs()) ||
        %Runtime.WebchatConfig{}

    now = System.system_time(:second)
    state = current_state(conn)

    case expired_reason(state, config, now) do
      nil ->
        conn
        |> maybe_put_session(@session_id_key, state.session_id || generate_session_id())
        |> maybe_put_session(@session_created_at_key, state.created_at || now)
        |> put_session(@session_last_active_at_key, now)
        |> clear_reset_reason()

      reason ->
        conn
        |> configure_session(renew: true)
        |> put_session(@session_id_key, generate_session_id())
        |> put_session(@session_created_at_key, now)
        |> put_session(@session_last_active_at_key, now)
        |> delete_session(@display_name_key)
        |> put_session(@reset_reason_key, reason)
    end
  end

  def renew(conn, reason \\ "manual_reset") do
    now = System.system_time(:second)

    conn
    |> configure_session(renew: true)
    |> put_session(@session_id_key, generate_session_id())
    |> put_session(@session_created_at_key, now)
    |> put_session(@session_last_active_at_key, now)
    |> delete_session(@display_name_key)
    |> put_session(@reset_reason_key, reason)
  end

  defp current_state(conn) do
    %{
      session_id: get_session(conn, @session_id_key),
      created_at: integer_session_value(conn, @session_created_at_key),
      last_active_at: integer_session_value(conn, @session_last_active_at_key)
    }
  end

  defp expired_reason(state, config, now) do
    cond do
      is_integer(state.created_at) and
          now - state.created_at > max(config.session_max_age_minutes, 1) * 60 ->
        "max_age"

      is_integer(state.last_active_at) and
          now - state.last_active_at > max(config.session_idle_timeout_minutes, 1) * 60 ->
        "idle_timeout"

      true ->
        nil
    end
  end

  defp integer_session_value(conn, key) do
    try do
      case get_session(conn, key) do
        value when is_integer(value) -> value
        value when is_binary(value) -> String.to_integer(value)
        _ -> nil
      end
    rescue
      ArgumentError -> nil
    end
  end

  defp maybe_put_session(conn, _key, nil), do: conn
  defp maybe_put_session(conn, key, value), do: put_session(conn, key, value)

  defp clear_reset_reason(conn) do
    if get_session(conn, @reset_reason_key),
      do: delete_session(conn, @reset_reason_key),
      else: conn
  end

  defp generate_session_id, do: Ecto.UUID.generate()
end
