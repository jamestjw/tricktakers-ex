defmodule TricktakersWeb.Game.RoundTest do
  use ExUnit.Case, async: true

  alias TricktakersWeb.Game.Round

  test "gold crown is not awarded when most tricks are tied" do
    game = game(%{king: 2, gambler: 2, hermit: 1})

    assert Round.gold_crown_winner_id(game) == nil
    assert Round.resolve(game).gold_crown_winner_id == nil
  end

  test "gold crown is awarded to the unique most tricks winner" do
    game = game(%{king: 3, gambler: 2, hermit: 0})

    assert Round.gold_crown_winner_id(game) == "king"
  end

  test "black crowns go to the two highest priority zero-trick players" do
    game = game(%{king: 5, gambler: 0, hermit: 0, berserker: 0})

    assert Round.black_crown_winner_ids(game) == ["gambler", "hermit"]
  end

  test "gambler character win requires bid 4 and exactly 4 tricks or all 5 tricks" do
    assert Round.character_winner_id(
             game(%{gambler: 4, king: 1}, %{"gambler" => %{"bid" => "4"}})
           ) == "gambler"

    assert Round.character_winner_id(
             game(%{gambler: 5, king: 0}, %{"gambler" => %{"bid" => "2"}})
           ) == "gambler"

    assert Round.character_winner_id(
             game(%{gambler: 3, king: 2}, %{"gambler" => %{"bid" => "3"}})
           ) == nil
  end

  test "berserker zero-trick character win only applies in round 3" do
    assert Round.character_winner_id(game(%{king: 5, berserker: 0}, %{}, 2)) == "king"

    assert Round.character_winner_id(game(%{king: 4, berserker: 0, gambler: 1}, %{}, 3)) ==
             "berserker"
  end

  test "crown victory requires two gold crowns or three black crowns" do
    game =
      game(%{king: 3, gambler: 2}, %{}, 1, %{
        "king" => %{gold: 1, black: 0},
        "gambler" => %{gold: 0, black: 2}
      })

    result = Round.resolve(game)

    assert result.gold_crown_winner_id == "king"
    assert result.crown_winner_id == "king"
    assert result.crowns["king"].gold == 2
  end

  test "scores king trick points and doubles only those points in round 3" do
    assert Round.resolve(game(%{king: 4, gambler: 1}, %{}, 1)).points_delta["king"] == 120
    assert Round.resolve(game(%{king: 4, gambler: 1}, %{}, 3)).points_delta["king"] == 240
  end

  test "scores gambler bid payout plus or minus wager" do
    made =
      Round.resolve(
        game(%{gambler: 3, king: 2}, %{"gambler" => %{"bid" => "3", "wager" => "40"}})
      )

    missed =
      Round.resolve(
        game(%{gambler: 2, king: 3}, %{"gambler" => %{"bid" => "3", "wager" => "40"}})
      )

    assert made.points_delta["gambler"] == 190
    assert missed.points_delta["gambler"] == 110
  end

  test "scores berserker and resistance points" do
    result = Round.resolve(game(%{berserker: 2, resistance: 3, king: 0}))

    assert result.points_delta["berserker"] == 30
    assert result.points_delta["resistance"] == 90
  end

  test "resistance scores revolt bonus when winning the revolt trick" do
    game =
      game(%{resistance: 1, king: 4})
      |> Map.put(:completed_tricks, [
        %{
          trick: 1,
          revolt?: true,
          winner_id: "resistance",
          plays: [
            %{player_id: "resistance", card: %{id: "white-flag", kind: :white_flag}},
            %{player_id: "king", card: %{id: "red-9", kind: :number, suit: :red, rank: 9}}
          ]
        }
      ])

    result = Round.resolve(game)

    assert result.points_delta["resistance"] == 60
  end

  test "resistance wins immediately by winning revolt with black" do
    game =
      game(%{resistance: 1, king: 4})
      |> Map.put(:completed_tricks, [
        %{
          trick: 1,
          revolt?: true,
          winner_id: "resistance",
          plays: [
            %{
              player_id: "resistance",
              card: %{id: "black-1", kind: :number, suit: :black, rank: 1}
            },
            %{player_id: "king", card: %{id: "rare", kind: :rare}}
          ]
        }
      ])

    assert Round.character_winner_id(game) == "resistance"
  end

  test "resistance is black-crown eligible when only win was the revolt trick" do
    game =
      game(%{resistance: 1, king: 4, gambler: 0})
      |> Map.put(:completed_tricks, [
        %{
          trick: 1,
          revolt?: true,
          winner_id: "resistance",
          plays: [
            %{player_id: "resistance", card: %{id: "white-flag", kind: :white_flag}},
            %{player_id: "king", card: %{id: "red-9", kind: :number, suit: :red, rank: 9}}
          ]
        }
      ])

    assert Round.black_crown_winner_ids(game) == ["gambler", "resistance"]
  end

  test "next lead goes to fewest points among players with no gold crown, priority breaking ties" do
    result =
      Round.resolve(
        game(%{king: 2, gambler: 2, hermit: 1}, %{}, 1, %{}, %{
          "king" => 50,
          "gambler" => 50,
          "hermit" => 100
        })
      )

    assert result.next_lead_player_id == "gambler"
  end

  defp game(trick_wins, setup_done \\ %{}, round \\ 1, crowns \\ %{}, points \\ nil) do
    character_picks =
      trick_wins
      |> Map.keys()
      |> Map.new(fn character -> {Atom.to_string(character), Atom.to_string(character)} end)

    points =
      points || Map.new(character_picks, fn {player_id, _character_id} -> {player_id, 30} end)

    %{
      round: round,
      trick_wins:
        Map.new(trick_wins, fn {character, wins} -> {Atom.to_string(character), wins} end),
      character_picks: character_picks,
      character_setup_done: setup_done,
      crowns: crowns,
      points: points
    }
  end
end
