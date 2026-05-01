defmodule TricktakersWebWeb.CharactersLive do
  use TricktakersWebWeb, :live_view

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}
end
