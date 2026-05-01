defmodule TricktakersWebWeb.RoomLive do
  use TricktakersWebWeb, :live_view

  alias TricktakersWeb.RoomRegistry

  @impl true
  def mount(params, _session, socket) do
    code = String.upcase(params["code"] || "")
    room = RoomRegistry.get_room(code)

    if connected?(socket) and room, do: RoomRegistry.subscribe_room(code)

    {:ok,
     socket
     |> assign(:room, room)
     |> assign(:code, code)
     |> assign(:join_error, nil)
     |> assign(:start_error, nil)
     |> assign(:player_name, String.trim(params["name"] || ""))
     |> assign(:join_form, to_form(%{"player_name" => ""}, as: :join))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket =
      assign(
        socket,
        :player_name,
        String.trim(params["name"] || socket.assigns.player_name || "")
      )

    socket = maybe_join_room(socket)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:room_updated, room}, socket) do
    {:noreply, assign(socket, :room, room)}
  end

  @impl true
  def handle_event("join_room", %{"join" => %{"player_name" => name}}, socket) do
    code = socket.assigns.code

    case RoomRegistry.join_room(code, name) do
      {:ok, _room} ->
        {:noreply,
         socket
         |> assign(:join_error, nil)
         |> assign(:player_name, String.trim(name))
         |> push_patch(to: ~p"/rooms/#{code}?name=#{String.trim(name)}")}

      {:error, reason} ->
        {:noreply, assign(socket, :join_error, reason)}
    end
  end

  def handle_event("start_game", _params, socket) do
    case RoomRegistry.start_game(socket.assigns.code, socket.assigns.player_name) do
      {:ok, room} ->
        {:noreply,
         push_navigate(socket, to: ~p"/games/#{room.code}?name=#{socket.assigns.player_name}")}

      {:error, reason} ->
        {:noreply, assign(socket, :start_error, reason)}
    end
  end

  defp maybe_join_room(%{assigns: %{room: nil}} = socket), do: socket

  defp maybe_join_room(socket) do
    name = socket.assigns.player_name

    if name == "" do
      socket
    else
      case RoomRegistry.join_room(socket.assigns.code, name) do
        {:ok, room} -> assign(socket, room: room, join_error: nil)
        {:error, reason} -> assign(socket, join_error: reason)
      end
    end
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
          <nav><.link navigate={~p"/lobby"}>Lobby</.link></nav>
        </div>

        <main class="page">
          <%= if is_nil(@room) do %>
            <div class="panel">
              <h1 class="h-2">Room not found</h1>
              <p class="body-sm" style="margin-top: 8px;">The room code may be invalid or expired.</p>
              <.link navigate={~p"/lobby"} class="btn" style="margin-top: 12px;">Back to lobby</.link>
            </div>
          <% else %>
            <div class="row between" style="align-items:flex-end;margin-bottom: 24px;">
              <div>
                <div class="eyebrow">Room code · {@room.code}</div>
                <h1 class="h-1" style="margin-top:6px;">{@room.name}</h1>
              </div>
              <span class="pill solid">{String.capitalize(to_string(@room.status))}</span>
            </div>

            <%= if @player_name == "" do %>
              <div class="panel" style="max-width: 420px;">
                <div class="h-3">Join room</div>
                <.form
                  for={@join_form}
                  id="room-join-form"
                  phx-submit="join_room"
                  class="col gap-3"
                  style="margin-top: 12px;"
                >
                  <.input field={@join_form[:player_name]} type="text" label="Your name" required />
                  <button type="submit" class="btn">Join</button>
                </.form>
                <%= if @join_error do %>
                  <p class="body-sm" style="color: var(--suit-red); margin-top: 8px;">
                    {@join_error}
                  </p>
                <% end %>
              </div>
            <% else %>
              <div style="display:grid;grid-template-columns:1fr 320px;gap:24px;">
                <section class="panel">
                  <div class="h-3">Players ({length(@room.players)} / {@room.max_players})</div>
                  <div class="col gap-2" style="margin-top: 12px;">
                    <%= for player <- @room.players do %>
                      <div
                        class="row between"
                        style="padding:10px 12px;border:1px solid var(--hair);border-radius:8px;"
                      >
                        <span>{player}</span>
                        <%= if player == @room.host do %>
                          <span class="pill">Host</span>
                        <% end %>
                      </div>
                    <% end %>
                  </div>
                </section>

                <aside class="panel">
                  <div class="eyebrow">Game settings</div>
                  <div class="body" style="margin-top:8px;">Mode: {@room.mode}</div>
                  <div class="body">Capacity: {@room.max_players} players</div>
                  <button
                    class="btn"
                    style="margin-top: 16px;"
                    phx-click="start_game"
                    disabled={@player_name != @room.host or @room.status != :waiting}
                  >
                    Start game
                  </button>
                  <%= if @start_error do %>
                    <p class="body-sm" style="color: var(--suit-red); margin-top: 8px;">
                      {@start_error}
                    </p>
                  <% end %>
                  <%= if @room.status == :in_progress do %>
                    <.link
                      navigate={~p"/games/#{@room.code}?name=#{@player_name}"}
                      class="btn ghost"
                      style="margin-top: 8px;"
                    >
                      Open game
                    </.link>
                  <% end %>
                </aside>
              </div>
            <% end %>
          <% end %>
        </main>
      </div>
    </Layouts.app>
    """
  end
end
