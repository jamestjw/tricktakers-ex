defmodule TricktakersWeb.Game.Deck do
  @moduledoc """
  Builders and dealing helpers for Tricktakers card decks.
  """

  alias TricktakersWeb.Game.Card

  @suits [:red, :blue, :green, :black]
  @ranks 1..9

  @spec standard_deck() :: [Card.t()]
  def standard_deck do
    number_cards() ++ rare_cards() ++ white_flag_cards()
  end

  @spec berserker_deck() :: [Card.t()]
  def berserker_deck do
    [%{id: "berserker", kind: :berserker}] ++
      for(suit <- @suits, do: %{id: "berserker-#{suit}-10", kind: :number, suit: suit, rank: 10}) ++
      [%{id: "berserker-rare", kind: :rare}, %{id: "berserker-white-flag", kind: :white_flag}]
  end

  @spec shuffle([Card.t()]) :: [Card.t()]
  def shuffle(cards), do: Enum.shuffle(cards)

  @spec deal([String.t()], pos_integer()) :: %{String.t() => [Card.t()]}
  def deal(player_ids, cards_per_player \\ 5) do
    {hands, _draw_pile} = deal_with_draw_pile(player_ids, cards_per_player)
    hands
  end

  @spec deal_with_draw_pile([String.t()], pos_integer()) ::
          {%{String.t() => [Card.t()]}, [Card.t()]}
  def deal_with_draw_pile(player_ids, cards_per_player \\ 5) do
    deck = shuffle(standard_deck())

    hands =
      player_ids
      |> Enum.with_index()
      |> Map.new(fn {player_id, index} ->
        hand =
          deck
          |> Enum.drop(index * cards_per_player)
          |> Enum.take(cards_per_player)

        {player_id, hand}
      end)

    draw_pile = Enum.drop(deck, length(player_ids) * cards_per_player)

    {hands, draw_pile}
  end

  defp number_cards do
    for suit <- @suits, rank <- @ranks do
      %{id: "#{suit}-#{rank}", kind: :number, suit: suit, rank: rank}
    end
  end

  defp rare_cards do
    [
      %{id: "rare-1", kind: :rare},
      %{id: "rare-2", kind: :rare}
    ]
  end

  defp white_flag_cards do
    [
      %{id: "white-flag-1", kind: :white_flag},
      %{id: "white-flag-2", kind: :white_flag}
    ]
  end
end
