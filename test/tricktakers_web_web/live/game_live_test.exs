defmodule TricktakersWebWeb.GameLiveTest do
  use TricktakersWebWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias TricktakersWeb.RoomRegistry

  test "auto-completes setup when the current character has no setup choices", %{conn: conn} do
    host_id = "auto-host-#{System.unique_integer([:positive])}"
    player_id = "auto-player-#{System.unique_integer([:positive])}"

    {:ok, room} =
      RoomRegistry.create_room(
        %{
          "player_name" => "Hermit",
          "room_name" => "Auto Setup",
          "max_players" => "2",
          "mode" => "Basic"
        },
        host_id
      )

    {:ok, room} = RoomRegistry.join_room(room.code, player_id, "Berserker")
    {:ok, room} = RoomRegistry.start_game(room.code, host_id)
    {:ok, room} = RoomRegistry.choose_character(room.code, host_id, "hermit")
    {:ok, room} = RoomRegistry.choose_character(room.code, player_id, "berserker")

    conn = Plug.Test.init_test_session(conn, %{"player_session_id" => host_id})

    {:ok, _view, html} = live(conn, ~p"/games/#{room.code}")

    room = RoomRegistry.get_room(room.code)

    assert Map.has_key?(room.game.character_setup_done, host_id)
    refute html =~ "No choice needed"
    refute html =~ "Complete setup"
  end
end
