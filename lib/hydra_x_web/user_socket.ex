defmodule HydraXWeb.UserSocket do
  use Phoenix.Socket

  alias HydraX.Runtime
  alias HydraXWeb.OperatorAuth

  channel "project:*", HydraXWeb.ProjectChannel
  channel "source:*", HydraXWeb.SourceChannel
  channel "product_conversation:*", HydraXWeb.ProductConversationChannel

  @impl true
  def connect(_params, socket, connect_info) do
    session = connect_info[:session] || %{}
    session_state = OperatorAuth.session_state(session)
    operator_configured? = Runtime.operator_password_configured?()

    cond do
      operator_configured? and not session_state.valid? ->
        :error

      true ->
        {:ok,
         socket
         |> assign(:operator_authenticated, not operator_configured? or session_state.valid?)
         |> assign(:operator_session, session_state)
         |> assign(:phoenix_ecto_sandbox, connect_info[:user_agent])}
    end
  end

  @impl true
  def id(_socket), do: nil
end
