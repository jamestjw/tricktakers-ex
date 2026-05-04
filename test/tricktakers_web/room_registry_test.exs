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

  test "gambler setup starts with 20 bonus points and redraws selected cards" do
    {room, host_id, player_id} = start_king_gambler_setup("Gambler Setup")

    assert room.game.points[player_id] == 50

    king_discard = room.game.hands[host_id] |> hd()

    {:ok, room} =
      RoomRegistry.complete_character_setup(room.code, host_id, %{"discard" => king_discard.id})

    original_hand = room.game.hands[player_id]
    redraw_cards = [Enum.at(original_hand, 1), Enum.at(original_hand, 3)]
    redraw_ids = Enum.map(redraw_cards, & &1.id)
    original_draw_pile = room.game.draw_pile

    {:ok, room} = RoomRegistry.redraw_gambler_hand(room.code, player_id, redraw_ids)

    gambler_hand = room.game.hands[player_id]
    gambler_hand_ids = Enum.map(gambler_hand, & &1.id)

    assert length(gambler_hand) == 5

    assert gambler_hand == [
             Enum.at(original_hand, 0),
             Enum.at(original_draw_pile, 0),
             Enum.at(original_hand, 2),
             Enum.at(original_draw_pile, 1),
             Enum.at(original_hand, 4)
           ]

    assert room.game.gambler_redraws[player_id] == 1
    assert Enum.all?(redraw_cards, &(&1 in room.game.discards))
    assert Enum.all?(Enum.take(original_draw_pile, 2), &(&1 in gambler_hand))
    refute Enum.any?(redraw_ids, &(&1 in gambler_hand_ids))
  end

  test "gambler setup stores bid and wager" do
    {room, host_id, player_id} = start_king_gambler_setup("Gambler Bid")

    king_discard = room.game.hands[host_id] |> hd()

    {:ok, room} =
      RoomRegistry.complete_character_setup(room.code, host_id, %{"discard" => king_discard.id})

    {:ok, room} =
      RoomRegistry.complete_character_setup(room.code, player_id, %{"bid" => "3", "wager" => "40"})

    assert room.game.character_setup_done[player_id] == %{"bid" => "3", "wager" => "40"}
  end

  test "gambler may wager up to 100 in round 3" do
    {room, host_id, player_id} = start_king_gambler_setup("Gambler Round 3")
    room = put_room_round(room, 3)

    king_discard = room.game.hands[host_id] |> hd()

    {:ok, room} =
      RoomRegistry.complete_character_setup(room.code, host_id, %{"discard" => king_discard.id})

    {:ok, room} =
      RoomRegistry.complete_character_setup(room.code, player_id, %{
        "bid" => "5",
        "wager" => "100"
      })

    assert room.game.round == 3
    assert room.game.character_setup_done[player_id] == %{"bid" => "5", "wager" => "100"}
  end

  defp start_king_gambler_setup(room_name) do
    host_id = "gambler-host-#{System.unique_integer([:positive])}"
    player_id = "gambler-player-#{System.unique_integer([:positive])}"

    {:ok, room} =
      RoomRegistry.create_room(
        %{
          "player_name" => "King",
          "room_name" => room_name,
          "max_players" => "2",
          "mode" => "Basic"
        },
        host_id
      )

    {:ok, room} = RoomRegistry.join_room(room.code, player_id, "Gambler")
    {:ok, room} = RoomRegistry.start_game(room.code, host_id)
    {:ok, room} = RoomRegistry.choose_character(room.code, host_id, "king")
    {:ok, room} = RoomRegistry.choose_character(room.code, player_id, "gambler")

    assert room.game.points[player_id] == 50

    {room, host_id, player_id}
  end

  defp put_room_round(room, round) do
    :sys.replace_state(RoomRegistry, fn state ->
      put_in(state, [:rooms, room.code, :game, :round], round)
    end)

    RoomRegistry.get_room(room.code)
  end
end
