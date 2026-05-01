defmodule TricktakersWebWeb.GameLive do
  use TricktakersWebWeb, :live_view

  alias TricktakersWeb.RoomRegistry

  @impl true
  def mount(params, _session, socket) do
    code = String.upcase(params["code"] || "")
    room = RoomRegistry.get_room(code)
    if connected?(socket) and room, do: RoomRegistry.subscribe_room(code)

    {:ok, assign(socket, room: room, player_name: String.trim(params["name"] || ""))}
  end

  @impl true
  def handle_info({:room_updated, room}, socket) do
    {:noreply, assign(socket, :room, room)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="app">
        <div class="app-bar">
          <.link navigate={~p"/lobby"} class="brand">
            <span class="glyph">T</span><span>Tricktakers</span>
          </.link>
          <nav>
            <.link navigate={
              if @room, do: ~p"/rooms/#{@room.code}?name=#{@player_name}", else: ~p"/lobby"
            }>
              Room
            </.link>
          </nav>
        </div>

        <main class="page-wide">
          <%= if is_nil(@room) do %>
            <div class="panel">
              <h1 class="h-2">Game not found</h1>
              <.link navigate={~p"/lobby"} class="btn" style="margin-top: 12px;">Back to lobby</.link>
            </div>
          <% else %>
            <div class="row between" style="align-items:flex-end;margin-bottom:24px;">
              <div>
                <div class="eyebrow">Live game · {@room.code}</div>
                <h1 class="h-1" style="margin-top:6px;">{@room.name}</h1>
              </div>
              <span class="pill solid">{@room.mode}</span>
            </div>

            <div class="panel-soft">
              <div class="row between" style="margin-bottom:16px;">
                <div class="h-3">
                  Round {(@room.game && @room.game.round) || 1} · Trick {(@room.game &&
                                                                            @room.game.trick) || 1}
                </div>
                <span class="pill">Lead · {(@room.game && @room.game.lead) || "-"}</span>
              </div>
              <div class="body muted">
                This is a real game session backed by in-memory state. Next step is wiring full trick logic from the rules engine.
              </div>
            </div>
          <% end %>
        </main>
      </div>
    </Layouts.app>
    """
  end
end
