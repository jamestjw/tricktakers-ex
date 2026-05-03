defmodule TricktakersWeb.RoomRegistryTest do
  use ExUnit.Case, async: false

  alias TricktakersWeb.RoomRegistry

  test "king setup adds king rare and discards the selected card" do
    host_id = "king-host-#{System.unique_integer([:positive])}"
    player_id = "king-player-#{System.unique_integer([:positive])}"

    {:ok, room} =
      RoomRegistry.create_room(
        %{
          "player_name" => "King",
          "room_name" => "King Setup",
          "max_players" => "2",
          "mode" => "Basic"
        },
        host_id
      )

    {:ok, room} = RoomRegistry.join_room(room.code, player_id, "Gambler")
    {:ok, room} = RoomRegistry.start_game(room.code, host_id)
    {:ok, room} = RoomRegistry.choose_character(room.code, host_id, "king")
    {:ok, room} = RoomRegistry.choose_character(room.code, player_id, "gambler")

    original_hand = get_in(room, [:game, :hands, host_id])
    discard = hd(original_hand)

    {:ok, room} =
      RoomRegistry.complete_character_setup(room.code, host_id, %{"discard" => discard.id})

    king_hand = get_in(room, [:game, :hands, host_id])
    king_hand_ids = Enum.map(king_hand, & &1.id)

    assert length(king_hand) == 5
    assert "king-rare" in king_hand_ids
    refute discard.id in king_hand_ids
    assert discard in room.game.discards
  end
end
