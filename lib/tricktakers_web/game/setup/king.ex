defmodule TricktakersWeb.Game.Setup.King do
  @moduledoc """
  Local UI state for King character setup.
  """

  @type t :: %__MODULE__{
          selected_discard_id: String.t() | nil
        }

  defstruct selected_discard_id: nil
end
