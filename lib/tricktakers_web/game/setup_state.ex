defmodule TricktakersWeb.Game.SetupState do
  @moduledoc """
  Typed LiveView UI state for the active character setup form.
  """

  alias TricktakersWeb.Game.Card
  alias TricktakersWeb.Game.Setup.Gambler
  alias TricktakersWeb.Game.Setup.King

  @type data :: King.t() | Gambler.t() | nil
  @type t :: %__MODULE__{
          character_id: String.t() | nil,
          hand: [Card.t()],
          data: data()
        }

  defstruct character_id: nil, hand: [], data: nil

  @spec new() :: t()
  def new, do: %__MODULE__{}

  @spec for_character(String.t() | nil, [Card.t()], non_neg_integer(), t()) :: t()
  def for_character("king", hand, _redraw_count, %__MODULE__{data: %King{} = data}) do
    %__MODULE__{character_id: "king", hand: hand, data: prune_king(data, hand)}
  end

  def for_character("king", hand, _redraw_count, _state) do
    %__MODULE__{character_id: "king", hand: hand, data: %King{}}
  end

  def for_character("gambler", hand, redraw_count, %__MODULE__{data: %Gambler{} = data}) do
    data = %Gambler{
      data
      | selected_discard_ids: prune_ids(data.selected_discard_ids, hand),
        redraw_count: redraw_count
    }

    %__MODULE__{character_id: "gambler", hand: hand, data: data}
  end

  def for_character("gambler", hand, redraw_count, _state) do
    %__MODULE__{character_id: "gambler", hand: hand, data: %Gambler{redraw_count: redraw_count}}
  end

  def for_character(character_id, hand, _redraw_count, _state) do
    %__MODULE__{character_id: character_id, hand: hand, data: nil}
  end

  @spec select_king_card(t(), String.t()) :: t()
  def select_king_card(%__MODULE__{} = state, card_id) do
    %__MODULE__{state | data: %King{selected_discard_id: card_id}}
  end

  @spec toggle_gambler_card(t(), String.t()) :: t()
  def toggle_gambler_card(%__MODULE__{data: %Gambler{} = data} = state, card_id) do
    selected_discard_ids =
      if card_id in data.selected_discard_ids do
        List.delete(data.selected_discard_ids, card_id)
      else
        data.selected_discard_ids ++ [card_id]
      end

    %__MODULE__{state | data: %Gambler{data | selected_discard_ids: selected_discard_ids}}
  end

  def toggle_gambler_card(%__MODULE__{} = state, card_id) do
    %__MODULE__{state | data: %Gambler{selected_discard_ids: [card_id]}}
  end

  @spec selected_king_card_id(t()) :: String.t() | nil
  def selected_king_card_id(%__MODULE__{data: %King{selected_discard_id: card_id}}), do: card_id
  def selected_king_card_id(_state), do: nil

  @spec selected_gambler_card_ids(t()) :: [String.t()]
  def selected_gambler_card_ids(%__MODULE__{data: %Gambler{selected_discard_ids: card_ids}}),
    do: card_ids

  def selected_gambler_card_ids(_state), do: []

  @spec redraw_count(t()) :: non_neg_integer()
  def redraw_count(%__MODULE__{data: %Gambler{redraw_count: redraw_count}}), do: redraw_count
  def redraw_count(_state), do: 0

  @spec clear_selections(t()) :: t()
  def clear_selections(%__MODULE__{data: %King{} = data} = state) do
    %__MODULE__{state | data: %King{data | selected_discard_id: nil}}
  end

  def clear_selections(%__MODULE__{data: %Gambler{} = data} = state) do
    %__MODULE__{state | data: %Gambler{data | selected_discard_ids: []}}
  end

  def clear_selections(%__MODULE__{} = state), do: state

  defp prune_king(%King{} = data, hand) do
    if data.selected_discard_id in hand_ids(hand),
      do: data,
      else: %King{data | selected_discard_id: nil}
  end

  defp prune_ids(card_ids, hand) do
    ids = hand_ids(hand)
    Enum.filter(card_ids, &(&1 in ids))
  end

  defp hand_ids(hand), do: Enum.map(hand, & &1.id)
end
