defmodule TricktakersWebWeb.LobbyLive do
  use TricktakersWebWeb, :live_view

  alias TricktakersWeb.RoomRegistry

  @impl true
  def mount(_params, session, socket) do
    if connected?(socket), do: RoomRegistry.subscribe_rooms()

    {:ok,
     socket
     |> assign(:player_session_id, session["player_session_id"])
     |> assign(:rooms, RoomRegistry.list_rooms())
     |> assign(:page, :landing)
     |> assign(:create_error, nil)
     |> assign(:join_error, nil)
     |> assign_create_form()
     |> assign_join_form()}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    page = if socket.assigns.live_action == :landing, do: :landing, else: :lobby
    {:noreply, assign(socket, :page, page)}
  end

  @impl true
  def handle_info({:rooms_updated, rooms}, socket) do
    {:noreply, assign(socket, :rooms, sort_rooms(rooms))}
  end

  @impl true
  def handle_event("create_room", %{"room" => params}, socket) do
    case RoomRegistry.create_room(params, socket.assigns.player_session_id) do
      {:ok, room} ->
        {:noreply,
         socket
         |> put_flash(:info, "Room created")
         |> assign(:create_error, nil)
         |> assign_create_form()
         |> push_navigate(to: ~p"/rooms/#{room.code}")}

      {:error, reason} ->
        {:noreply, assign(socket, :create_error, reason)}
    end
  end

  def handle_event("join_by_code", %{"join" => params}, socket) do
    code = String.trim(params["code"] || "") |> String.upcase()
    name = String.trim(params["player_name"] || "")
    room = if code == "", do: nil, else: RoomRegistry.get_room(code)

    cond do
      code == "" ->
        {:noreply, assign(socket, :join_error, "Room code is required")}

      room && RoomRegistry.player_in_room?(room, socket.assigns.player_session_id) ->
        {:noreply,
         socket
         |> assign(:join_error, nil)
         |> push_navigate(to: joined_room_path(room))}

      name == "" ->
        {:noreply, assign(socket, :join_error, "Player name is required")}

      true ->
        {:noreply,
         socket
         |> assign(:join_error, nil)
         |> push_navigate(to: ~p"/rooms/#{code}?name=#{name}")}
    end
  end

  defp assign_create_form(socket) do
    defaults = %{"player_name" => "", "room_name" => "", "max_players" => "4", "mode" => "Basic"}
    assign(socket, :create_form, to_form(defaults, as: :room))
  end

  defp assign_join_form(socket) do
    assign(socket, :join_form, to_form(%{"player_name" => "", "code" => ""}, as: :join))
  end

  defp joined_room_path(%{status: :in_progress, code: code}), do: ~p"/games/#{code}"
  defp joined_room_path(%{code: code}), do: ~p"/rooms/#{code}"

  defp sort_rooms(rooms), do: Enum.sort_by(rooms, & &1.inserted_at, {:desc, DateTime})

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="app">
        <.app_bar active={@page} />
        <%= if @page == :landing do %>
          <main class="page" style="padding-top: 80px;">
            <div style="display: grid; grid-template-columns: 1.1fr 0.9fr; gap: 64px; align-items: center;">
              <div>
                <div class="eyebrow">A trick-taking card game by Hiroken · 2-5 players</div>
                <h1 class="tt-display" style="margin: 16px 0 24px; max-width: 12ch;">
                  Eight characters.<br />One crown.
                </h1>
                <p class="body" style="max-width: 56ch; color: var(--ink-2);">
                  Create a room, bring your friends, and play TRICKTAKERs in real time.
                </p>
                <div class="row gap-3" style="margin-top: 32px;">
                  <.link navigate={~p"/lobby"} class="btn lg">Go to lobby →</.link>
                  <.link navigate={~p"/characters"} class="btn lg ghost">Character guide</.link>
                </div>
              </div>
              <div class="panel-soft">
                <div class="tt-heading-3">How it works</div>
                <div class="body muted" style="margin-top:8px;">
                  Create a room, share the code, and start when everyone is seated.
                </div>
              </div>
            </div>
          </main>
        <% else %>
          <main class="page">
            <div class="row between" style="margin-bottom: 24px; align-items: flex-end;">
              <div>
                <div class="eyebrow">Lobby</div>
                <h1 class="tt-heading-2" style="margin-top: 6px;">Find a table.</h1>
              </div>
            </div>

            <div style="display:grid;grid-template-columns:1fr 320px;gap:24px;">
              <section class="col gap-3">
                <%= if @rooms == [] do %>
                  <div class="panel">
                    <div class="tt-heading-3">No active rooms yet</div>
                    <p class="body-sm" style="margin-top: 8px;">Create one from the right panel.</p>
                  </div>
                <% else %>
                  <%= for room <- @rooms do %>
                    <div class="room">
                      <div class="meta">
                        <div class="row gap-3">
                          <span class="name">{room.name}</span>
                          <span class={if(room.status == :waiting, do: "pill solid", else: "pill")}>
                            {if room.status == :waiting, do: "Open", else: "In progress"}
                          </span>
                        </div>
                        <div class="sub">
                          <span>Code · {room.code}</span>
                          <span>Host · {room.host}</span>
                          <span>{room.mode}</span>
                        </div>
                      </div>
                      <div class="right">
                        <span class="mono">{length(room.players)} / {room.max_players}</span>
                        <.link navigate={~p"/rooms/#{room.code}"} class="btn">Open →</.link>
                      </div>
                    </div>
                  <% end %>
                <% end %>
              </section>

              <aside class="col gap-3">
                <div class="panel">
                  <div class="tt-heading-3">Create room</div>
                  <.form
                    for={@create_form}
                    id="create-room-form"
                    phx-submit="create_room"
                    class="col gap-3"
                    style="margin-top: 12px;"
                  >
                    <div class="field">
                      <label for="create-player-name">Your name</label>
                      <input
                        id="create-player-name"
                        name="room[player_name]"
                        value={@create_form[:player_name].value}
                        class="input"
                        type="text"
                        required
                      />
                    </div>
                    <div class="field">
                      <label for="create-room-name">Room name</label>
                      <input
                        id="create-room-name"
                        name="room[room_name]"
                        value={@create_form[:room_name].value}
                        class="input"
                        type="text"
                        required
                      />
                    </div>
                    <div class="field">
                      <label for="create-max-players">Max players</label>
                      <select id="create-max-players" name="room[max_players]" class="input">
                        <option
                          value="2"
                          selected={to_string(@create_form[:max_players].value) == "2"}
                        >
                          2
                        </option>
                        <option
                          value="3"
                          selected={to_string(@create_form[:max_players].value) == "3"}
                        >
                          3
                        </option>
                        <option
                          value="4"
                          selected={to_string(@create_form[:max_players].value) == "4"}
                        >
                          4
                        </option>
                        <option
                          value="5"
                          selected={to_string(@create_form[:max_players].value) == "5"}
                        >
                          5
                        </option>
                      </select>
                    </div>
                    <div class="field">
                      <label for="create-mode">Game mode</label>
                      <select id="create-mode" name="room[mode]" class="input">
                        <option
                          value="Basic"
                          selected={to_string(@create_form[:mode].value) == "Basic"}
                        >
                          Basic
                        </option>
                        <option
                          value="Advanced"
                          selected={to_string(@create_form[:mode].value) == "Advanced"}
                        >
                          Advanced
                        </option>
                      </select>
                      <p class="body-sm" style="margin-top: 4px;">
                        Basic uses the five core characters. Advanced enables the full character roster.
                      </p>
                    </div>
                    <button type="submit" class="btn">Create room</button>
                  </.form>
                  <%= if @create_error do %>
                    <p class="body-sm" style="color: var(--suit-red); margin-top: 10px;">
                      {@create_error}
                    </p>
                  <% end %>
                </div>

                <div class="panel">
                  <div class="tt-heading-3">Join by code</div>
                  <.form
                    for={@join_form}
                    id="join-room-form"
                    phx-submit="join_by_code"
                    class="col gap-3"
                    style="margin-top: 12px;"
                  >
                    <div class="field">
                      <label for="join-player-name">Your name</label>
                      <input
                        id="join-player-name"
                        name="join[player_name]"
                        value={@join_form[:player_name].value}
                        class="input"
                        type="text"
                        required
                      />
                    </div>
                    <div class="field">
                      <label for="join-room-code">Room code</label>
                      <input
                        id="join-room-code"
                        name="join[code]"
                        value={@join_form[:code].value}
                        class="input"
                        type="text"
                        required
                      />
                    </div>
                    <button type="submit" class="btn ghost">Go to room</button>
                  </.form>
                  <%= if @join_error do %>
                    <p class="body-sm" style="color: var(--suit-red); margin-top: 10px;">
                      {@join_error}
                    </p>
                  <% end %>
                </div>
              </aside>
            </div>
          </main>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  attr :active, :atom, required: true

  defp app_bar(assigns) do
    ~H"""
    <div class="app-bar">
      <.link navigate={~p"/"} class="brand">
        <span class="glyph">T</span><span>Tricktakers</span>
      </.link>
      <nav>
        <.link navigate={~p"/"} aria-current={if(@active == :landing, do: "page", else: nil)}>
          Landing
        </.link>
        <.link navigate={~p"/lobby"} aria-current={if(@active == :lobby, do: "page", else: nil)}>
          Lobby
        </.link>
        <.link navigate={~p"/characters"}>Characters</.link>
      </nav>
    </div>
    """
  end
end
