defmodule TricktakersWebWeb.PageControllerTest do
  use TricktakersWebWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == "/tricktakers/index.html"
  end
end
