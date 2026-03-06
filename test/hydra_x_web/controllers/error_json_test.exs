defmodule HydraXWeb.ErrorJSONTest do
  use HydraXWeb.ConnCase, async: true
  @tag seed_default_agent: false

  test "renders 404" do
    assert HydraXWeb.ErrorJSON.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}
  end

  test "renders 500" do
    assert HydraXWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end
