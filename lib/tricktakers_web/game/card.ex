defmodule TricktakersWeb.Game.Card do
  @moduledoc """
  Card types for the standard Tricktakers deck.
  """

  @type suit :: :red | :blue | :green | :black
  @type rank :: 1..9

  @type number_card :: %{
          required(:id) => String.t(),
          required(:kind) => :number,
          required(:suit) => suit(),
          required(:rank) => rank()
        }

  @type rare_card :: %{
          required(:id) => String.t(),
          required(:kind) => :rare
        }

  @type white_flag_card :: %{
          required(:id) => String.t(),
          required(:kind) => :white_flag
        }

  @type t :: number_card() | rare_card() | white_flag_card()
end
