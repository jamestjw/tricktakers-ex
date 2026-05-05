defmodule TricktakersWeb.Game.Trick do
  @moduledoc """
  Trick-play legality and winner resolution.
  """

  alias TricktakersWeb.Game.Card

  @type play :: %{required(:player_id) => String.t(), required(:card) => Card.t()}

  @spec lead_suit([play()]) :: Card.suit() | nil
  def lead_suit(plays) do
    plays
    |> Enum.find_value(fn
      %{card: %{kind: :number, suit: suit}} -> suit
      _play -> nil
    end)
  end

  @spec legal_cards([Card.t()], [play()]) :: [Card.t()]
  def legal_cards(hand, []), do: hand

  def legal_cards(hand, plays) do
    case lead_suit(plays) do
      nil ->
        hand

      suit ->
        suited_cards = Enum.filter(hand, &number_suit?(&1, suit))

        if suited_cards == [] do
          hand
        else
          Enum.filter(hand, fn card -> colorless?(card) or number_suit?(card, suit) end)
        end
    end
  end

  @spec legal_card?([Card.t()], Card.t(), [play()]) :: boolean()
  def legal_card?(hand, card, plays) do
    Enum.any?(legal_cards(hand, plays), &(&1.id == card.id))
  end

  @spec winning_play([play()], keyword()) :: play() | nil
  def winning_play(plays, opts \\ [])

  def winning_play([], _opts), do: nil

  def winning_play(plays, opts) do
    suit = lead_suit(plays)
    revolt? = Keyword.get(opts, :revolt?, false)

    if revolt? do
      plays
      |> Enum.with_index()
      |> Enum.min_by(fn {play, index} -> {revolt_card_strength(play.card), index} end)
      |> elem(0)
    else
      plays
      |> Enum.with_index()
      |> Enum.max_by(fn {play, index} -> {card_strength(play.card, suit), -index} end)
      |> elem(0)
    end
  end

  defp card_strength(%{kind: :rare}, _lead_suit), do: 300
  defp card_strength(%{kind: :white_flag}, _lead_suit), do: 0
  defp card_strength(%{kind: :number, suit: :black, rank: rank}, _lead_suit), do: 200 + rank
  defp card_strength(%{kind: :number, suit: suit, rank: rank}, suit), do: 100 + rank
  defp card_strength(%{kind: :number, rank: rank}, _lead_suit), do: rank

  defp revolt_card_strength(%{kind: :white_flag}), do: 0
  defp revolt_card_strength(%{kind: :number, suit: :black, rank: rank}), do: 100 + rank
  defp revolt_card_strength(%{kind: :number, rank: rank}), do: rank
  defp revolt_card_strength(%{kind: :rare}), do: 200

  defp colorless?(%{kind: kind}), do: kind in [:rare, :white_flag]
  defp number_suit?(%{kind: :number, suit: card_suit}, suit), do: card_suit == suit
  defp number_suit?(_card, _suit), do: false
end
