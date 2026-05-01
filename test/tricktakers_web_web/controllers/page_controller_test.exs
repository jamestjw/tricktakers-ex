defmodule TricktakersWebWeb.PageControllerTest do
  use TricktakersWebWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Tricktakers"
  end
end
