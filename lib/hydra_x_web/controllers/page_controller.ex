defmodule HydraXWeb.PageController do
  use HydraXWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
