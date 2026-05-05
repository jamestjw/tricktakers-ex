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

  test "current player can play a legal card to the current trick" do
    {room, host_id, player_id} = start_playing_game("Legal Play")
    red_3 = %{id: "test-red-3", kind: :number, suit: :red, rank: 3}
    blue_5 = %{id: "test-blue-5", kind: :number, suit: :blue, rank: 5}
    room = put_player_hands(room, %{host_id => [red_3], player_id => [blue_5]})

    {:ok, room} = RoomRegistry.play_card(room.code, host_id, red_3.id)

    assert room.game.current_trick == [%{player_id: host_id, card: red_3}]
    assert room.game.current_player == player_id
    assert room.game.hands[host_id] == []
  end

  test "non-current player cannot play" do
    {room, _host_id, player_id} = start_playing_game("Wrong Turn")
    card = hd(room.game.hands[player_id])

    assert {:error, "It is not your turn to play"} =
             RoomRegistry.play_card(room.code, player_id, card.id)
  end

  test "player must follow lead suit when able" do
    {room, host_id, player_id} = start_playing_game("Follow Suit")
    red_3 = %{id: "test-red-3", kind: :number, suit: :red, rank: 3}
    red_7 = %{id: "test-red-7", kind: :number, suit: :red, rank: 7}
    blue_5 = %{id: "test-blue-5", kind: :number, suit: :blue, rank: 5}
    room = put_player_hands(room, %{host_id => [red_3], player_id => [blue_5, red_7]})

    {:ok, room} = RoomRegistry.play_card(room.code, host_id, red_3.id)

    assert {:error, "You must follow the lead suit if able"} =
             RoomRegistry.play_card(room.code, player_id, blue_5.id)

    {:ok, room} = RoomRegistry.play_card(room.code, player_id, red_7.id)

    assert room.game.completed_tricks == [
             %{
               trick: 1,
               lead_suit: :red,
               plays: [%{player_id: host_id, card: red_3}, %{player_id: player_id, card: red_7}],
               winner_id: player_id
             }
           ]

    assert room.game.current_player == player_id
    assert room.game.trick_wins[player_id] == 1
  end

  test "player may play any card when unable to follow suit" do
    {room, host_id, player_id} = start_playing_game("Cannot Follow")
    red_3 = %{id: "test-red-3", kind: :number, suit: :red, rank: 3}
    blue_5 = %{id: "test-blue-5", kind: :number, suit: :blue, rank: 5}
    room = put_player_hands(room, %{host_id => [red_3], player_id => [blue_5]})

    {:ok, room} = RoomRegistry.play_card(room.code, host_id, red_3.id)
    assert {:ok, room} = RoomRegistry.play_card(room.code, player_id, blue_5.id)
    assert room.game.trick_wins[host_id] == 1
  end

  test "rare and white flag can be played while holding the lead suit" do
    {room, host_id, player_id} = start_playing_game("Colorless Plays")
    red_3 = %{id: "test-red-3", kind: :number, suit: :red, rank: 3}
    red_7 = %{id: "test-red-7", kind: :number, suit: :red, rank: 7}
    rare = %{id: "test-rare", kind: :rare}
    room = put_player_hands(room, %{host_id => [red_3], player_id => [red_7, rare]})

    {:ok, room} = RoomRegistry.play_card(room.code, host_id, red_3.id)
    assert {:ok, room} = RoomRegistry.play_card(room.code, player_id, rare.id)

    assert room.game.completed_tricks == [
             %{
               trick: 1,
               lead_suit: :red,
               plays: [%{player_id: host_id, card: red_3}, %{player_id: player_id, card: rare}],
               winner_id: player_id
             }
           ]

    white_flag = %{id: "test-white-flag", kind: :white_flag}
    black_9 = %{id: "test-black-9", kind: :number, suit: :black, rank: 9}
    red_9 = %{id: "test-red-9", kind: :number, suit: :red, rank: 9}
    room = put_player_hands(room, %{player_id => [black_9], host_id => [red_9, white_flag]})

    {:ok, room} = RoomRegistry.play_card(room.code, player_id, black_9.id)
    assert {:ok, room} = RoomRegistry.play_card(room.code, host_id, white_flag.id)
    assert room.game.trick_wins[player_id] == 2
  end

  test "colorless lead does not create a suit obligation until a number card is played" do
    {room, host_id, player_id} = start_playing_game("Colorless Lead")
    rare = %{id: "test-rare", kind: :rare}
    red_7 = %{id: "test-red-7", kind: :number, suit: :red, rank: 7}
    blue_5 = %{id: "test-blue-5", kind: :number, suit: :blue, rank: 5}
    room = put_player_hands(room, %{host_id => [rare], player_id => [red_7, blue_5]})

    {:ok, room} = RoomRegistry.play_card(room.code, host_id, rare.id)
    assert {:ok, room} = RoomRegistry.play_card(room.code, player_id, blue_5.id)

    assert [%{lead_suit: :blue, winner_id: ^host_id}] = room.game.completed_tricks
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

  defp start_playing_game(room_name) do
    {room, host_id, player_id} = start_king_gambler_setup(room_name)

    king_discard = room.game.hands[host_id] |> hd()

    {:ok, room} =
      RoomRegistry.complete_character_setup(room.code, host_id, %{"discard" => king_discard.id})

    {:ok, room} =
      RoomRegistry.complete_character_setup(room.code, player_id, %{"bid" => "2", "wager" => "20"})

    assert room.game.phase == :playing
    {room, host_id, player_id}
  end

  defp put_player_hands(room, hands) do
    :sys.replace_state(RoomRegistry, fn state ->
      Enum.reduce(hands, state, fn {player_id, hand}, state ->
        put_in(state, [:rooms, room.code, :game, :hands, player_id], hand)
      end)
    end)

    RoomRegistry.get_room(room.code)
  end

  defp put_room_round(room, round) do
    :sys.replace_state(RoomRegistry, fn state ->
      put_in(state, [:rooms, room.code, :game, :round], round)
    end)

    RoomRegistry.get_room(room.code)
  end
end
