defmodule HydraXWeb.ErrorHTMLTest do
  use HydraXWeb.ConnCase, async: true
  @moduletag seed_default_agent: false

  # Bring render_to_string/4 for testing custom views
  import Phoenix.Template, only: [render_to_string: 4]

  test "renders 404.html" do
    assert render_to_string(HydraXWeb.ErrorHTML, "404", "html", []) == "Not Found"
  end

  test "renders 500.html" do
    assert render_to_string(HydraXWeb.ErrorHTML, "500", "html", []) == "Internal Server Error"
  end
end
