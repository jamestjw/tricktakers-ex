defmodule TricktakersWeb.Game.Round do
  @moduledoc """
  Round-end character win and crown resolution.
  """

  @type result :: %{
          character_winner_id: String.t() | nil,
          gold_crown_winner_id: String.t() | nil,
          black_crown_winner_ids: [String.t()],
          crown_winner_id: String.t() | nil,
          crowns: %{String.t() => %{gold: non_neg_integer(), black: non_neg_integer()}},
          points_before: %{String.t() => integer()},
          points_delta: %{String.t() => integer()},
          points_after: %{String.t() => non_neg_integer()},
          next_lead_player_id: String.t() | nil
        }

  @spec resolve(map()) :: result()
  def resolve(game) do
    character_winner_id = character_winner_id(game)
    points_before = Map.get(game, :points, %{})

    if character_winner_id do
      %{
        character_winner_id: character_winner_id,
        gold_crown_winner_id: nil,
        black_crown_winner_ids: [],
        crown_winner_id: nil,
        crowns: Map.get(game, :crowns, %{}),
        points_before: points_before,
        points_delta: zero_points(game),
        points_after: points_before,
        next_lead_player_id: nil
      }
    else
      two_player? = Map.get(game, :two_player?, false)
      gold_crown_winner_id = if two_player?, do: nil, else: gold_crown_winner_id(game)
      black_crown_winner_ids = if two_player?, do: [], else: black_crown_winner_ids(game)
      points_delta = points_delta(game)
      points_after = apply_points(points_before, points_delta)

      crowns =
        if two_player? do
          Map.get(game, :crowns, %{})
        else
          award_crowns(Map.get(game, :crowns, %{}), gold_crown_winner_id, black_crown_winner_ids)
        end

      %{
        character_winner_id: nil,
        gold_crown_winner_id: gold_crown_winner_id,
        black_crown_winner_ids: black_crown_winner_ids,
        crown_winner_id: if(two_player?, do: nil, else: crown_winner_id(crowns)),
        crowns: crowns,
        points_before: points_before,
        points_delta: points_delta,
        points_after: points_after,
        next_lead_player_id: next_lead_player_id(game, points_after, crowns)
      }
    end
  end

  @spec points_delta(map()) :: %{String.t() => integer()}
  def points_delta(game) do
    Map.new(game.character_picks || %{}, fn {player_id, character_id} ->
      {player_id, score_player(game, player_id, character_id)}
    end)
  end

  @spec character_winner_id(map()) :: String.t() | nil
  def character_winner_id(game) do
    game.character_picks
    |> Enum.filter(fn {player_id, character_id} ->
      character_win?(game, player_id, character_id)
    end)
    |> highest_priority_player()
  end

  @spec gold_crown_winner_id(map()) :: String.t() | nil
  def gold_crown_winner_id(game) do
    trick_wins = Map.get(game, :trick_wins, %{})
    player_ids = Map.keys(game.character_picks || %{})
    max_wins = player_ids |> Enum.map(&Map.get(trick_wins, &1, 0)) |> Enum.max(fn -> 0 end)

    winners = Enum.filter(player_ids, &(Map.get(trick_wins, &1, 0) == max_wins))

    if length(winners) == 1, do: hd(winners), else: nil
  end

  @spec black_crown_winner_ids(map()) :: [String.t()]
  def black_crown_winner_ids(game) do
    game.character_picks
    |> Enum.filter(fn {player_id, character_id} ->
      black_crown_eligible?(game, player_id, character_id)
    end)
    |> Enum.sort_by(fn {_player_id, character_id} -> character_priority_rank(character_id) end)
    |> Enum.take(2)
    |> Enum.map(fn {player_id, _character_id} -> player_id end)
  end

  defp character_win?(game, player_id, "king"), do: trick_wins(game, player_id) == 5
  defp character_win?(game, player_id, "hermit"), do: trick_wins(game, player_id) == 5

  defp character_win?(game, player_id, "gambler") do
    wins = trick_wins(game, player_id)
    bid = get_in(game, [:character_setup_done, player_id, "bid"])

    wins == 5 or (bid == "4" and wins == 4)
  end

  defp character_win?(game, player_id, "berserker") do
    game.round == 3 and trick_wins(game, player_id) == 0
  end

  defp character_win?(game, player_id, "resistance") do
    case revolt_trick_won_by(game, player_id) do
      %{plays: plays} ->
        case winning_card_for(plays, player_id) do
          %{kind: :number, suit: :black} -> true
          _card -> false
        end

      nil ->
        false
    end
  end

  defp character_win?(_game, _player_id, _character_id), do: false

  defp trick_wins(game, player_id), do: Map.get(game.trick_wins || %{}, player_id, 0)

  defp score_player(game, player_id, "king") do
    points =
      %{0 => 0, 1 => 20, 2 => 50, 3 => 80, 4 => 120} |> Map.get(trick_wins(game, player_id), 0)

    if game.round == 3, do: points * 2, else: points
  end

  defp score_player(game, player_id, "gambler") do
    setup = get_in(game, [:character_setup_done, player_id]) || %{}
    bid = parse_int(setup["bid"])
    wager = parse_int(setup["wager"])
    bid_points = %{0 => 30, 1 => 60, 2 => 90, 3 => 150, 4 => 150, 5 => 200} |> Map.get(bid, 0)

    if trick_wins(game, player_id) == bid do
      bid_points + wager * 2
    else
      bid_points - wager
    end
  end

  defp score_player(game, player_id, "resistance") do
    final_round_trick_points = if game.round == 3, do: trick_wins(game, player_id) * 30, else: 0
    final_round_trick_points + resistance_revolt_bonus(game, player_id)
  end

  defp score_player(game, player_id, "hermit") do
    %{0 => 50, 1 => -10, 2 => -30, 3 => 70, 4 => 100} |> Map.get(trick_wins(game, player_id), 0)
  end

  defp score_player(game, player_id, "berserker") do
    %{0 => -30, 1 => -10, 2 => 30, 3 => 50, 4 => 80, 5 => -50}
    |> Map.get(trick_wins(game, player_id), 0)
  end

  defp score_player(_game, _player_id, _character_id), do: 0

  defp parse_int(value) do
    case Integer.parse(to_string(value || "0")) do
      {integer, ""} -> integer
      _ -> 0
    end
  end

  defp zero_points(game), do: game.character_picks |> Map.keys() |> Map.new(&{&1, 0})

  defp black_crown_eligible?(game, player_id, "resistance") do
    Map.get(game.trick_wins || %{}, player_id, 0) == 0 or
      resistance_only_won_revolt?(game, player_id)
  end

  defp black_crown_eligible?(game, player_id, _character_id),
    do: Map.get(game.trick_wins || %{}, player_id, 0) == 0

  defp resistance_only_won_revolt?(game, player_id) do
    Map.get(game.trick_wins || %{}, player_id, 0) == 1 and
      not is_nil(revolt_trick_won_by(game, player_id))
  end

  defp resistance_revolt_bonus(game, player_id) do
    case revolt_trick_won_by(game, player_id) do
      %{plays: plays} ->
        plays
        |> winning_card_for(player_id)
        |> revolt_bonus_for_card()

      nil ->
        0
    end
  end

  defp revolt_bonus_for_card(%{kind: :white_flag}), do: 30
  defp revolt_bonus_for_card(%{kind: :number, rank: rank}) when rank in 1..3, do: 50
  defp revolt_bonus_for_card(%{kind: :number, rank: rank}) when rank in 4..6, do: 80
  defp revolt_bonus_for_card(%{kind: :number, rank: rank}) when rank in 7..9, do: 100
  defp revolt_bonus_for_card(_card), do: 0

  defp revolt_trick_won_by(game, player_id) do
    game
    |> Map.get(:completed_tricks, [])
    |> Enum.find(fn trick ->
      Map.get(trick, :revolt?, false) and trick.winner_id == player_id
    end)
  end

  defp winning_card_for(plays, player_id) do
    plays
    |> Enum.find(&(&1.player_id == player_id))
    |> case do
      nil -> nil
      play -> play.card
    end
  end

  defp apply_points(points_before, points_delta) do
    Map.new(points_before, fn {player_id, points} ->
      {player_id, max(points + Map.get(points_delta, player_id, 0), 0)}
    end)
  end

  defp next_lead_player_id(game, points_after, crowns) do
    game.character_picks
    |> Enum.reject(fn {player_id, _character_id} ->
      get_in(crowns, [player_id, :gold]) |> Kernel.||(0) > 0
    end)
    |> case do
      [] -> Map.to_list(game.character_picks || %{})
      candidates -> candidates
    end
    |> Enum.min_by(fn {player_id, character_id} ->
      {Map.get(points_after, player_id, 0), character_priority_rank(character_id)}
    end)
    |> elem(0)
  end

  defp award_crowns(crowns, gold_crown_winner_id, black_crown_winner_ids) do
    crowns
    |> award_gold(gold_crown_winner_id)
    |> award_black(black_crown_winner_ids)
  end

  defp award_gold(crowns, nil), do: crowns

  defp award_gold(crowns, player_id), do: update_crown_count(crowns, player_id, :gold)

  defp award_black(crowns, player_ids) do
    Enum.reduce(player_ids, crowns, &update_crown_count(&2, &1, :black))
  end

  defp update_crown_count(crowns, player_id, crown) do
    initial_counts = Map.put(%{gold: 0, black: 0}, crown, 1)

    Map.update(crowns, player_id, initial_counts, fn counts ->
      Map.update(counts, crown, 1, &(&1 + 1))
    end)
  end

  defp crown_winner_id(crowns) do
    crowns
    |> Enum.find_value(fn {player_id, counts} ->
      if Map.get(counts, :gold, 0) >= 2 or Map.get(counts, :black, 0) >= 3 do
        player_id
      end
    end)
  end

  defp highest_priority_player([]), do: nil

  defp highest_priority_player(players) do
    players
    |> Enum.min_by(fn {_player_id, character_id} -> character_priority_rank(character_id) end)
    |> elem(0)
  end

  defp character_priority_rank("king"), do: 1
  defp character_priority_rank("gambler"), do: 2
  defp character_priority_rank("resistance"), do: 3
  defp character_priority_rank("adventurer"), do: 4
  defp character_priority_rank("hermit"), do: 5
  defp character_priority_rank("collector"), do: 6
  defp character_priority_rank("berserker"), do: 7
  defp character_priority_rank("ruler"), do: 8
  defp character_priority_rank(_character_id), do: 99
end
