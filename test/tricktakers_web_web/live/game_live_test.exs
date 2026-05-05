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

  test "renders round complete summary", %{conn: conn} do
    host_id = "summary-host-#{System.unique_integer([:positive])}"
    player_id = "summary-player-#{System.unique_integer([:positive])}"

    {:ok, room} =
      RoomRegistry.create_room(
        %{
          "player_name" => "King",
          "room_name" => "Round Summary",
          "max_players" => "2",
          "mode" => "Basic"
        },
        host_id
      )

    {:ok, room} = RoomRegistry.join_room(room.code, player_id, "Gambler")
    {:ok, room} = RoomRegistry.start_game(room.code, host_id)

    round_result = %{
      character_winner_id: nil,
      gold_crown_winner_id: host_id,
      black_crown_winner_ids: [player_id],
      crown_winner_id: nil,
      crowns: %{host_id => %{gold: 1, black: 0}, player_id => %{gold: 0, black: 1}},
      points_before: %{host_id => 30, player_id => 50},
      points_delta: %{host_id => 50, player_id => 30},
      points_after: %{host_id => 80, player_id => 80},
      next_lead_player_id: player_id
    }

    :sys.replace_state(RoomRegistry, fn state ->
      state
      |> put_in([:rooms, room.code, :game, :phase], :round_complete)
      |> put_in([:rooms, room.code, :game, :round_result], round_result)
      |> put_in([:rooms, room.code, :game, :character_picks], %{
        host_id => "king",
        player_id => "gambler"
      })
      |> put_in([:rooms, room.code, :game, :trick_wins], %{host_id => 3, player_id => 0})
      |> put_in([:rooms, room.code, :game, :points], round_result.points_after)
      |> put_in([:rooms, room.code, :game, :winner_id], nil)
      |> put_in([:rooms, room.code, :game, :win_reason], nil)
    end)

    conn = Plug.Test.init_test_session(conn, %{"player_session_id" => host_id})

    {:ok, _view, html} = live(conn, ~p"/games/#{room.code}")

    assert html =~ "Round results."
    assert html =~ "King · 3 tricks"
    assert html =~ "+50 pts"
    assert html =~ "Gold crown"
    assert html =~ "Black crowns"
    assert html =~ "Gambler gets the lead player token."
    assert html =~ "Continue to round 2"
  end

  test "renders final points tiebreak summary without continue action", %{conn: conn} do
    host_id = "points-host-#{System.unique_integer([:positive])}"
    player_id = "points-player-#{System.unique_integer([:positive])}"

    {:ok, room} =
      RoomRegistry.create_room(
        %{
          "player_name" => "King",
          "room_name" => "Point Summary",
          "max_players" => "2",
          "mode" => "Basic"
        },
        host_id
      )

    {:ok, room} = RoomRegistry.join_room(room.code, player_id, "Gambler")
    {:ok, room} = RoomRegistry.start_game(room.code, host_id)

    round_result = %{
      character_winner_id: nil,
      gold_crown_winner_id: nil,
      black_crown_winner_ids: [],
      crown_winner_id: nil,
      crowns: %{host_id => %{gold: 0, black: 0}, player_id => %{gold: 0, black: 0}},
      points_before: %{host_id => 80, player_id => 70},
      points_delta: %{host_id => 20, player_id => 30},
      points_after: %{host_id => 100, player_id => 100},
      next_lead_player_id: player_id
    }

    :sys.replace_state(RoomRegistry, fn state ->
      state
      |> put_in([:rooms, room.code, :game, :phase], :round_complete)
      |> put_in([:rooms, room.code, :game, :round], 5)
      |> put_in([:rooms, room.code, :game, :round_result], round_result)
      |> put_in([:rooms, room.code, :game, :character_picks], %{
        host_id => "king",
        player_id => "gambler"
      })
      |> put_in([:rooms, room.code, :game, :trick_wins], %{host_id => 1, player_id => 3})
      |> put_in([:rooms, room.code, :game, :points], round_result.points_after)
      |> put_in([:rooms, room.code, :game, :winner_id], host_id)
      |> put_in([:rooms, room.code, :game, :win_reason], :points)
    end)

    conn = Plug.Test.init_test_session(conn, %{"player_session_id" => host_id})

    {:ok, _view, html} = live(conn, ~p"/games/#{room.code}")

    assert html =~ "Final points victory"
    assert html =~ "King wins by final points."
    assert html =~ "Final points were tied, so character precedence broke the tie."
    refute html =~ "Continue to round 6"
  end

  test "lead token holder chooses first trick lead after setup", %{conn: conn} do
    host_id = "lead-host-#{System.unique_integer([:positive])}"
    player_id = "lead-player-#{System.unique_integer([:positive])}"

    {:ok, room} =
      RoomRegistry.create_room(
        %{
          "player_name" => "King",
          "room_name" => "Lead Choice",
          "max_players" => "2",
          "mode" => "Basic"
        },
        host_id
      )

    {:ok, room} = RoomRegistry.join_room(room.code, player_id, "Gambler")
    {:ok, room} = RoomRegistry.start_game(room.code, host_id)

    :sys.replace_state(RoomRegistry, fn state ->
      state
      |> put_in([:rooms, room.code, :game, :phase], :choosing_first_lead)
      |> put_in([:rooms, room.code, :game, :round], 2)
      |> put_in([:rooms, room.code, :game, :lead_player_token_id], player_id)
      |> put_in([:rooms, room.code, :game, :character_picks], %{
        host_id => "king",
        player_id => "gambler"
      })
    end)

    conn = Plug.Test.init_test_session(conn, %{"player_session_id" => player_id})

    {:ok, view, html} = live(conn, ~p"/games/#{room.code}")

    assert html =~ "Choose the first lead."
    assert html =~ "Gambler holds the token"

    view
    |> element("#choose-first-lead-#{host_id}")
    |> render_click()

    room = RoomRegistry.get_room(room.code)

    assert room.game.phase == :playing
    assert room.game.lead == host_id
    assert room.game.current_player == host_id
  end
end
