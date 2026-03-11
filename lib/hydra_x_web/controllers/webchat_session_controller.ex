defmodule HydraXWeb.WebchatSessionController do
  use HydraXWeb, :controller

  alias HydraX.Runtime
  alias HydraXWeb.Plugs.WebchatSession

  def create(conn, %{"webchat_identity" => params}) do
    display_name =
      params
      |> Map.get("display_name", "")
      |> String.trim()
      |> String.slice(0, 80)

    config =
      Runtime.enabled_webchat_config() || List.first(Runtime.list_webchat_configs()) ||
        %Runtime.WebchatConfig{}

    cond do
      display_name == "" and not config.allow_anonymous_messages ->
        conn
        |> put_flash(:error, "Webchat requires a display name before sending messages.")
        |> redirect(to: ~p"/webchat")

      display_name == "" ->
        conn
        |> delete_session(:webchat_display_name)
        |> put_flash(:info, "Webchat session is browsing anonymously.")
        |> redirect(to: ~p"/webchat")

      true ->
        conn
        |> put_session(:webchat_display_name, display_name)
        |> put_flash(:info, "Webchat identity updated.")
        |> redirect(to: ~p"/webchat")
    end
  end

  def delete(conn, _params) do
    conn
    |> WebchatSession.renew()
    |> put_flash(:info, "Webchat session reset.")
    |> redirect(to: ~p"/webchat")
  end
end
