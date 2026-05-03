defmodule TricktakersWeb.Game.Setup.Gambler do
  @moduledoc """
  Local UI state for Gambler character setup.
  """

  @type t :: %__MODULE__{
          selected_discard_ids: [String.t()],
          redraw_count: non_neg_integer()
        }

  defstruct selected_discard_ids: [], redraw_count: 0
end
