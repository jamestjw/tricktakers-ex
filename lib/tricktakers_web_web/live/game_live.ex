defmodule TricktakersWebWeb.GameLive do
  use TricktakersWebWeb, :live_view

  alias TricktakersWeb.Game.SetupState
  alias TricktakersWeb.Game.Trick
  alias TricktakersWeb.RoomRegistry

  @impl true
  def mount(params, session, socket) do
    code = String.upcase(params["code"] || "")
    room = RoomRegistry.get_room(code)
    player_session_id = session["player_session_id"]
    connected? = connected?(socket)
    if connected? and room, do: RoomRegistry.subscribe_room(code)

    socket =
      socket
      |> assign(:room, room)
      |> assign(:player_session_id, player_session_id)
      |> assign(:player_name, (room && RoomRegistry.player_name(room, player_session_id)) || "")
      |> assign(:selected_character_id, nil)
      |> assign(:setup_state, SetupState.new())
      |> assign(:selection_error, nil)
      |> assign(:setup_error, nil)
      |> assign(:revolt_ready?, false)
      |> assign(:black_crown_selected_card_ids, [])

    socket = if connected?, do: maybe_auto_complete_setup(socket), else: socket

    {:ok, socket}
  end

  @impl true
  def handle_info({:room_updated, room}, socket) do
    player_name =
      RoomRegistry.player_name(room, socket.assigns.player_session_id) ||
        socket.assigns.player_name

    {:noreply,
     socket
     |> assign(room: room, player_name: player_name)
     |> assign(
       :setup_state,
       setup_state_for(room, socket.assigns.player_session_id, socket.assigns.setup_state)
     )
     |> assign(
       :black_crown_selected_card_ids,
       selected_black_crown_card_ids(
         room,
         socket.assigns.player_session_id,
         socket.assigns.black_crown_selected_card_ids
       )
     )
     |> maybe_auto_complete_setup()}
  end

  @impl true
  def handle_event("select_character", %{"character" => character_id}, socket) do
    {:noreply, assign(socket, selected_character_id: character_id, selection_error: nil)}
  end

  def handle_event(
        "confirm_character",
        _params,
        %{assigns: %{selected_character_id: nil}} = socket
      ) do
    {:noreply, assign(socket, :selection_error, "Choose a character before confirming")}
  end

  def handle_event("confirm_character", _params, socket) do
    case RoomRegistry.choose_character(
           socket.assigns.room.code,
           socket.assigns.player_session_id,
           socket.assigns.selected_character_id
         ) do
      {:ok, room} ->
        {:noreply, assign(socket, room: room, selected_character_id: nil, selection_error: nil)}

      {:error, reason} ->
        {:noreply, assign(socket, :selection_error, reason)}
    end
  end

  def handle_event("select_setup_card", %{"card" => card_id}, socket) do
    {:noreply,
     assign(socket,
       setup_state: SetupState.select_king_card(socket.assigns.setup_state, card_id),
       setup_error: nil
     )}
  end

  def handle_event("toggle_gambler_card", %{"card" => card_id}, socket) do
    {:noreply,
     assign(socket,
       setup_state: SetupState.toggle_gambler_card(socket.assigns.setup_state, card_id),
       setup_error: nil
     )}
  end

  def handle_event("redraw_gambler_hand", _params, socket) do
    case RoomRegistry.redraw_gambler_hand(
           socket.assigns.room.code,
           socket.assigns.player_session_id,
           SetupState.selected_gambler_card_ids(socket.assigns.setup_state)
         ) do
      {:ok, room} ->
        setup_state =
          room
          |> setup_state_for(socket.assigns.player_session_id, socket.assigns.setup_state)
          |> SetupState.clear_selections()

        {:noreply, assign(socket, room: room, setup_state: setup_state, setup_error: nil)}

      {:error, reason} ->
        {:noreply, assign(socket, :setup_error, reason)}
    end
  end

  def handle_event("toggle_black_crown_card", %{"card" => card_id}, socket) do
    selected_card_ids = socket.assigns.black_crown_selected_card_ids

    selected_card_ids =
      if card_id in selected_card_ids,
        do: List.delete(selected_card_ids, card_id),
        else: selected_card_ids ++ [card_id]

    {:noreply, assign(socket, black_crown_selected_card_ids: selected_card_ids, setup_error: nil)}
  end

  def handle_event("redraw_black_crown_hand", _params, socket) do
    case RoomRegistry.redraw_black_crown_hand(
           socket.assigns.room.code,
           socket.assigns.player_session_id,
           socket.assigns.black_crown_selected_card_ids
         ) do
      {:ok, room} ->
        {:noreply,
         assign(socket, room: room, black_crown_selected_card_ids: [], setup_error: nil)}

      {:error, reason} ->
        {:noreply, assign(socket, :setup_error, reason)}
    end
  end

  def handle_event("skip_black_crown_redraw", _params, socket) do
    case RoomRegistry.skip_black_crown_redraw(
           socket.assigns.room.code,
           socket.assigns.player_session_id
         ) do
      {:ok, room} ->
        {:noreply,
         assign(socket, room: room, black_crown_selected_card_ids: [], setup_error: nil)}

      {:error, reason} ->
        {:noreply, assign(socket, :setup_error, reason)}
    end
  end

  def handle_event("complete_character_setup", params, socket) do
    setup_params = Map.get(params, "character_setup", %{})

    if current_setup_character_id(socket.assigns.room) == "king" and
         String.trim(setup_params["discard"] || "") == "" do
      {:noreply, assign(socket, :setup_error, "Choose one card to discard")}
    else
      case RoomRegistry.complete_character_setup(
             socket.assigns.room.code,
             socket.assigns.player_session_id,
             setup_params
           ) do
        {:ok, room} ->
          {:noreply,
           assign(socket,
             room: room,
             setup_state: SetupState.clear_selections(socket.assigns.setup_state),
             setup_error: nil
           )}

        {:error, reason} ->
          {:noreply, assign(socket, :setup_error, reason)}
      end
    end
  end

  def handle_event("play_card", %{"card" => card_id}, socket) do
    case RoomRegistry.play_card(
           socket.assigns.room.code,
           socket.assigns.player_session_id,
           card_id,
           socket.assigns.revolt_ready?
         ) do
      {:ok, room} ->
        {:noreply, assign(socket, room: room, setup_error: nil, revolt_ready?: false)}

      {:error, reason} ->
        {:noreply, assign(socket, :setup_error, reason)}
    end
  end

  def handle_event("draw_hermit_card", _params, socket) do
    case RoomRegistry.draw_hermit_card(socket.assigns.room.code, socket.assigns.player_session_id) do
      {:ok, room} -> {:noreply, assign(socket, room: room, setup_error: nil)}
      {:error, reason} -> {:noreply, assign(socket, :setup_error, reason)}
    end
  end

  def handle_event("discard_hermit_card", %{"card" => card_id}, socket) do
    case RoomRegistry.discard_hermit_card(
           socket.assigns.room.code,
           socket.assigns.player_session_id,
           card_id
         ) do
      {:ok, room} -> {:noreply, assign(socket, room: room, setup_error: nil)}
      {:error, reason} -> {:noreply, assign(socket, :setup_error, reason)}
    end
  end

  def handle_event("declare_kakumei", _params, socket) do
    if can_declare_kakumei?(socket.assigns.room.game, socket.assigns.player_session_id) do
      {:noreply, assign(socket, revolt_ready?: true, setup_error: nil)}
    else
      {:noreply, assign(socket, :setup_error, "Kakumei must be declared while playing your card")}
    end
  end

  def handle_event("continue_next_round", _params, socket) do
    case RoomRegistry.continue_next_round(
           socket.assigns.room.code,
           socket.assigns.player_session_id
         ) do
      {:ok, room} ->
        {:noreply,
         assign(socket,
           room: room,
           selected_character_id: nil,
           selection_error: nil,
           setup_error: nil,
           setup_state: SetupState.new()
         )}

      {:error, reason} ->
        {:noreply, assign(socket, :setup_error, reason)}
    end
  end

  def handle_event("choose_first_lead", %{"player" => player_id}, socket) do
    case RoomRegistry.choose_first_lead(
           socket.assigns.room.code,
           socket.assigns.player_session_id,
           player_id
         ) do
      {:ok, room} ->
        {:noreply, assign(socket, room: room, setup_error: nil)}

      {:error, reason} ->
        {:noreply, assign(socket, :setup_error, reason)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="app game-app">
        <.game_bar room={@room} />

        <main>
          <%= if is_nil(@room) do %>
            <div class="page panel">
              <h1 class="tt-heading-2">Game not found</h1>
              <.link navigate={~p"/lobby"} class="btn" style="margin-top: 12px;">Back to lobby</.link>
            </div>
          <% else %>
            <%= if not player_in_room?(@room, @player_session_id) do %>
              <div class="page panel">
                <div class="eyebrow">Game in progress</div>
                <h1 class="tt-heading-2" style="margin-top: 6px;">This table is already seated.</h1>
                <p class="body-sm" style="margin-top: 8px; max-width: 48ch;">
                  Only players who joined before the game started can open this table.
                </p>
                <.link navigate={~p"/lobby"} class="btn" style="margin-top: 12px;">
                  Back to lobby
                </.link>
              </div>
            <% else %>
              <%= case game_phase(@room) do %>
                <% :character_selection -> %>
                  <.character_selection_phase
                    room={@room}
                    player_session_id={@player_session_id}
                    selected_character_id={@selected_character_id}
                    selection_error={@selection_error}
                  />
                <% :character_setup -> %>
                  <.character_setup_phase
                    room={@room}
                    player_session_id={@player_session_id}
                    setup_state={@setup_state}
                    setup_error={@setup_error}
                  />
                <% :black_crown_redraw -> %>
                  <.black_crown_redraw_phase
                    room={@room}
                    player_session_id={@player_session_id}
                    selected_card_ids={@black_crown_selected_card_ids}
                    setup_error={@setup_error}
                  />
                <% :round_complete -> %>
                  <.round_complete_phase
                    room={@room}
                    player_session_id={@player_session_id}
                    setup_error={@setup_error}
                  />
                <% :choosing_first_lead -> %>
                  <.choosing_first_lead_phase
                    room={@room}
                    player_session_id={@player_session_id}
                    setup_error={@setup_error}
                  />
                <% _phase -> %>
                  <.active_table
                    room={@room}
                    player_session_id={@player_session_id}
                    play_error={@setup_error}
                    revolt_ready?={@revolt_ready?}
                  />
              <% end %>
            <% end %>
          <% end %>
        </main>
      </div>
    </Layouts.app>
    """
  end

  attr :room, :map, required: true
  attr :player_session_id, :string, required: true
  attr :selected_character_id, :string, default: nil
  attr :selection_error, :string, default: nil

  defp character_selection_phase(assigns) do
    assigns =
      assigns
      |> assign(:setup, character_selection_state(assigns.room, assigns.player_session_id))
      |> assign(:selected_character, character_by_id(assigns.selected_character_id))

    ~H"""
    <section id="character-selection" class="game-setup page-wide">
      <header class="game-setup-header">
        <div>
          <div class="eyebrow">Round {@setup.round} of {@setup.rounds} · Setup phase</div>
          <h1 class="tt-heading-1 game-setup-title">Choose your character.</h1>
          <p class="body game-setup-copy">
            Each round starts with character selection. {@room.mode} mode exposes {@setup.available_count} characters; players choose one at a time in lead order.
          </p>
        </div>
        <div class="status-row game-setup-status">
          <.progress_dots current={@setup.current_pick_number} total={@setup.total_picks} />
          <div class="sep"></div>
          <span>
            <strong class="mono">{@setup.current_picker}</strong>
            <%= if @setup.your_turn? do %>
              <span>is you</span>
            <% else %>
              <span>is choosing</span>
            <% end %>
          </span>
          <div class="sep"></div>
          <span class="mono muted">{@room.code}</span>
        </div>
      </header>

      <div class="game-setup-layout">
        <div>
          <div class="row gap-3 game-setup-filters">
            <span class="pill solid">{@room.mode} ({@setup.available_count})</span>
            <%= if @room.mode == "Advanced" do %>
              <span class="pill">Basic 5</span>
              <span class="pill">Advanced 3</span>
            <% else %>
              <span class="pill">Core roster</span>
            <% end %>
          </div>

          <div id="character-grid" class="game-character-grid">
            <%= for character <- @setup.characters do %>
              <.character_option
                character={character}
                taken_by={Map.get(@setup.taken_by, character.id)}
                disabled={not @setup.your_turn?}
                selected={@selected_character_id == character.id}
              />
            <% end %>
          </div>

          <div class="game-hand-preview">
            <div class="eyebrow">Your hand for this round</div>
            <div class="panel-soft game-hand-preview-panel">
              <div class="row gap-3 center-x">
                <%= for card <- @setup.hand_preview do %>
                  <.playing_card card={card} />
                <% end %>
              </div>
              <p class="body-sm game-hand-preview-copy">
                Strong on Black 1 and Red. Character choice should match both your hand and table position.
              </p>
            </div>
          </div>
        </div>

        <aside class="game-setup-sidebar">
          <div class="panel">
            <div class="eyebrow">Selection order</div>
            <div class="game-picker-list">
              <%= for picker <- @setup.pickers do %>
                <div class={["game-picker-row", picker.current? && "current", picker.you? && "you"]}>
                  <div class="row gap-2">
                    <span class={["avatar", picker.avatar_class]}>{picker.initial}</span>
                    <div>
                      <div class="tt-heading-4">
                        {picker.name}{if picker.you?, do: " (you)", else: ""}
                      </div>
                      <div class="body-sm muted">
                        <%= if picker.character do %>
                          Picked {picker.character.name}
                        <% else %>
                          Waiting to choose
                        <% end %>
                      </div>
                    </div>
                  </div>
                  <%= cond do %>
                    <% picker.character -> %>
                      <span class="pill solid">{picker.character.priority}</span>
                    <% picker.current? -> %>
                      <span class="pill gold">Choosing</span>
                    <% true -> %>
                      <span class="pill">Pending</span>
                  <% end %>
                </div>
              <% end %>
            </div>

            <%= if @selection_error do %>
              <p class="body-sm game-selection-error">{@selection_error}</p>
            <% end %>
          </div>

          <div class="panel-soft">
            <div class="eyebrow">Selection</div>
            <%= if @setup.your_turn? do %>
              <%= if @selected_character do %>
                <div class="game-selected-character">
                  <div class="tt-heading-3">{@selected_character.name}</div>
                  <div class="body-sm muted">
                    {@selected_character.priority} · {@selected_character.tag}
                  </div>
                  <p class="body-sm game-setup-note">{@selected_character.ability}</p>
                  <button
                    type="button"
                    id="confirm-character-button"
                    class="btn lg game-confirm-character"
                    phx-click="confirm_character"
                  >
                    Confirm character
                  </button>
                </div>
              <% else %>
                <p class="body game-setup-note">
                  It is your turn. Pick a character to preview it, then confirm when ready.
                </p>
              <% end %>
            <% else %>
              <p class="body game-setup-note">
                Waiting on <strong>{@setup.current_picker}</strong>. You can review the available roster, but choices are locked until your turn.
              </p>
            <% end %>
          </div>
        </aside>
      </div>
    </section>
    """
  end

  attr :room, :map, required: true
  attr :player_session_id, :string, required: true
  attr :setup_state, :map, required: true
  attr :setup_error, :string, default: nil

  defp character_setup_phase(assigns) do
    assigns =
      assigns
      |> assign(:setup, character_setup_state(assigns.room, assigns.player_session_id))
      |> assign(
        :setup_state,
        setup_state_for(assigns.room, assigns.player_session_id, assigns.setup_state)
      )

    ~H"""
    <section id="character-setup" class="game-setup page-wide">
      <header class="game-setup-header">
        <div>
          <div class="eyebrow">Round {@setup.round} of {@setup.rounds} · Character setup</div>
          <h1 class="tt-heading-1 game-setup-title">Resolve character setup.</h1>
          <p class="body game-setup-copy">
            Characters resolve setup in priority order. Some characters need a choice before trick play can begin.
          </p>
        </div>
        <div class="status-row game-setup-status">
          <.progress_dots current={@setup.current_setup_number} total={@setup.total_setups} />
          <div class="sep"></div>
          <span>
            <%= if @setup.your_turn? do %>
              <span>Your turn to setup</span>
            <% else %>
              <strong class="mono">{@setup.current_player}</strong>
              <span>is setting up</span>
            <% end %>
          </span>
          <div class="sep"></div>
          <span class="mono muted">{@room.code}</span>
        </div>
      </header>

      <div class="game-setup-layout">
        <section class="panel game-character-setup-card">
          <div class="eyebrow">Current character</div>
          <div class="game-character-setup-head">
            <div>
              <div class="tt-heading-2">{@setup.current_character.name}</div>
              <div class="body-sm muted">
                {@setup.current_character.priority} · {@setup.current_character.tag}
              </div>
            </div>
            <span class="pill solid">{@setup.current_character.points}</span>
          </div>
          <p class="body game-setup-copy">{@setup.current_character.ability}</p>

          <%= cond do %>
            <% @setup.your_turn? and setup_requires_input?(@setup.current_character.id) -> %>
              <.character_setup_form
                character={@setup.current_character}
                setup_state={@setup_state}
              />
            <% @setup.your_turn? -> %>
              <div class="panel-soft game-waiting-card">
                <div class="tt-heading-3">Resolving automatically</div>
                <p class="body-sm">
                  This character does not need setup choices right now. The game will continue automatically.
                </p>
              </div>
            <% true -> %>
              <div class="panel-soft game-waiting-card">
                <div class="tt-heading-3">Waiting for {@setup.current_player}</div>
                <p class="body-sm">
                  They are resolving {@setup.current_character.name}. You will continue automatically when setup reaches your character or play begins.
                </p>
              </div>
          <% end %>

          <%= if @setup_error do %>
            <p class="body-sm game-selection-error">{@setup_error}</p>
          <% end %>
        </section>

        <aside class="game-setup-sidebar">
          <div class="panel">
            <div class="eyebrow">Setup order</div>
            <div class="game-picker-list">
              <%= for player <- @setup.players do %>
                <div class={["game-picker-row", player.current? && "current", player.you? && "you"]}>
                  <div class="row gap-2">
                    <span class={["avatar", player.avatar_class]}>{player.initial}</span>
                    <div>
                      <div class="tt-heading-4">
                        {player.name}{if player.you?, do: " (you)", else: ""}
                      </div>
                      <div class="body-sm muted">{player.character.name}</div>
                    </div>
                  </div>
                  <%= cond do %>
                    <% player.done? -> %>
                      <span class="pill solid">Done</span>
                    <% player.current? -> %>
                      <span class="pill gold">Setting up</span>
                    <% true -> %>
                      <span class="pill">Pending</span>
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>

          <div class="panel-soft">
            <div class="eyebrow">Next phase</div>
            <p class="body game-setup-note">
              Once every selected character is set up, the table opens for Trick 1.
            </p>
          </div>
        </aside>
      </div>
    </section>
    """
  end

  attr :room, :map, required: true
  attr :player_session_id, :string, required: true
  attr :selected_card_ids, :list, required: true
  attr :setup_error, :string, default: nil

  defp black_crown_redraw_phase(assigns) do
    assigns =
      assign(
        assigns,
        :state,
        black_crown_redraw_state(
          assigns.room,
          assigns.player_session_id,
          assigns.selected_card_ids
        )
      )

    ~H"""
    <section id="black-crown-redraw" class="game-setup page-wide">
      <header class="game-setup-header">
        <div>
          <div class="eyebrow">Round 3 of 3 · Black crown redraw</div>
          <h1 class="tt-heading-1 game-setup-title">Spend black crowns or skip.</h1>
          <p class="body game-setup-copy">
            Each black crown buys one separate redraw: discard any number of cards and draw the same number from the standard draw pile.
          </p>
        </div>
        <div class="status-row game-setup-status">
          <span class="pill solid">{@state.waiting_label}</span>
          <div class="sep"></div>
          <span class="mono muted">{@room.code}</span>
        </div>
      </header>

      <div class="game-setup-layout">
        <section class="panel game-character-setup-card">
          <%= if @state.your_turn? do %>
            <div class="eyebrow">Your redraw</div>
            <div class="game-character-setup-head">
              <div class="tt-heading-2">{@state.crowns_left} black crowns available</div>
              <span class="pill solid">{@state.selected_count} selected</span>
            </div>
            <.setup_hand_selector
              id="black-crown-redraw-hand"
              hand={@state.hand}
              label="Choose cards to replace, or redraw without discarding"
              selected_card_ids={@selected_card_ids}
              event="toggle_black_crown_card"
              selectable={true}
            />
            <div class="row gap-2" style="margin-top: 16px;">
              <button
                id="redraw-black-crown-hand"
                type="button"
                class="btn"
                phx-click="redraw_black_crown_hand"
              >
                Spend black crown ({@state.crowns_left} left)
              </button>
              <button
                id="skip-black-crown-redraw"
                type="button"
                class="btn ghost"
                phx-click="skip_black_crown_redraw"
              >
                Skip redraw
              </button>
            </div>
          <% else %>
            <div class="panel-soft game-waiting-card">
              <div class="tt-heading-3">Waiting for crown redraws</div>
              <p class="body-sm">{@state.waiting_label}</p>
            </div>
          <% end %>

          <%= if @setup_error do %>
            <p class="body-sm game-selection-error">{@setup_error}</p>
          <% end %>
        </section>
      </div>
    </section>
    """
  end

  attr :character, :map, required: true
  attr :setup_state, :map, required: true

  defp character_setup_form(assigns) do
    assigns =
      assigns
      |> assign(:form, to_form(%{}, as: :character_setup))
      |> assign(:selected_king_card_id, SetupState.selected_king_card_id(assigns.setup_state))
      |> assign(
        :selected_gambler_card_ids,
        SetupState.selected_gambler_card_ids(assigns.setup_state)
      )
      |> assign(:gambler_redraw_count, SetupState.redraw_count(assigns.setup_state))

    ~H"""
    <.form
      for={@form}
      id={"#{@character.id}-setup-form"}
      phx-submit="complete_character_setup"
      class="game-character-setup-form"
    >
      <%= case @character.id do %>
        <% "king" -> %>
          <input type="hidden" name="character_setup[discard]" value={@selected_king_card_id || ""} />
          <.setup_hand_selector
            id="king-discard-hand"
            hand={@setup_state.hand}
            label="Discard one card after taking the King's Rare"
            selected_card_id={@selected_king_card_id}
            selectable={true}
          />
        <% "gambler" -> %>
          <.setup_hand_selector
            id="gambler-reference-hand"
            hand={@setup_state.hand}
            label="Choose cards to discard"
            selected_card_ids={@selected_gambler_card_ids}
            event="toggle_gambler_card"
            selectable={true}
          />
          <div class="panel-soft game-gambler-redraw-card">
            <div>
              <div class="tt-heading-4">Redraw before bidding</div>
              <p class="body-sm muted">
                Discard any number of selected cards, then draw back up to 5. You can redraw up to twice before locking your bid and wager.
              </p>
            </div>
            <button
              type="button"
              class="btn sm"
              phx-click="redraw_gambler_hand"
              disabled={@gambler_redraw_count >= 2 or @selected_gambler_card_ids == []}
            >
              Redraw hand ({2 - @gambler_redraw_count} left)
            </button>
          </div>
          <div class="game-form-grid">
            <div class="field">
              <label for="gambler-bid">Bid</label>
              <select id="gambler-bid" name="character_setup[bid]" class="input" required>
                <%= for bid <- 0..5 do %>
                  <option value={bid}>{bid} tricks</option>
                <% end %>
              </select>
            </div>
            <div class="field">
              <label for="gambler-wager">Wager</label>
              <select id="gambler-wager" name="character_setup[wager]" class="input" required>
                <%= for wager <- [0, 10, 20, 30, 40, 50] do %>
                  <option value={wager}>{wager} pts</option>
                <% end %>
              </select>
            </div>
          </div>
        <% _character_id -> %>
          <input type="hidden" name="character_setup[notes]" value="auto" />
      <% end %>

      <%= if setup_requires_input?(@character.id) do %>
        <button type="submit" class="btn lg">Complete setup</button>
      <% end %>
    </.form>
    """
  end

  attr :id, :string, required: true
  attr :hand, :list, required: true
  attr :label, :string, required: true
  attr :selected_card_id, :string, default: nil
  attr :selected_card_ids, :list, default: []
  attr :event, :string, default: "select_setup_card"
  attr :selectable, :boolean, default: false

  defp setup_hand_selector(assigns) do
    ~H"""
    <div class="game-setup-hand-field">
      <div class="field-label">{@label}</div>
      <div id={@id} class="game-setup-hand" role={if @selectable, do: "radiogroup", else: nil}>
        <%= for card <- @hand do %>
          <button
            id={"#{@id}-#{card.id}"}
            type="button"
            class={[
              "game-setup-card-button",
              setup_card_selected?(@selected_card_id, @selected_card_ids, card.id) && "selected",
              not @selectable && "read-only"
            ]}
            phx-click={if @selectable, do: @event, else: nil}
            phx-value-card={if @selectable, do: card.id, else: nil}
            disabled={!@selectable}
            aria-checked={
              if @selectable,
                do: setup_card_selected?(@selected_card_id, @selected_card_ids, card.id),
                else: nil
            }
            role={if @selectable, do: setup_card_role(@event), else: nil}
            title={card_label(card)}
          >
            <.playing_card card={card} />
          </button>
        <% end %>
      </div>
      <%= if @selectable do %>
        <p class="body-sm muted game-setup-hand-hint">
          {setup_hand_hint(@event, @selected_card_id, @selected_card_ids)}
        </p>
      <% end %>
    </div>
    """
  end

  defp setup_card_selected?(selected_card_id, selected_card_ids, card_id) do
    selected_card_id == card_id or card_id in selected_card_ids
  end

  defp setup_card_role(event) when event in ["toggle_gambler_card", "toggle_black_crown_card"],
    do: "checkbox"

  defp setup_card_role(_event), do: "radio"

  defp setup_hand_hint("toggle_gambler_card", _selected_card_id, []),
    do: "Select any cards you want to discard."

  defp setup_hand_hint("toggle_gambler_card", _selected_card_id, selected_card_ids),
    do: "#{length(selected_card_ids)} selected; redraw will replace that many cards."

  defp setup_hand_hint("toggle_black_crown_card", _selected_card_id, []),
    do: "Select cards to replace, or spend a crown without discarding."

  defp setup_hand_hint("toggle_black_crown_card", _selected_card_id, selected_card_ids),
    do: "#{length(selected_card_ids)} selected; this redraw will replace that many cards."

  defp setup_hand_hint(_event, selected_card_id, _selected_card_ids) do
    if selected_card_id,
      do: "Selected card will be discarded.",
      else: "Select a card to discard."
  end

  attr :character, :map, required: true
  attr :taken_by, :string, default: nil
  attr :disabled, :boolean, default: false
  attr :selected, :boolean, default: false

  defp character_option(assigns) do
    assigns = assign(assigns, :taken?, not is_nil(assigns.taken_by))

    ~H"""
    <button
      id={"character-#{@character.id}"}
      type="button"
      class={["char-card", "game-character-option", @taken? && "taken", @selected && "selected"]}
      phx-click="select_character"
      phx-value-character={@character.id}
      disabled={@taken? or @disabled}
      aria-label={character_button_label(@character, @taken_by, @disabled)}
    >
      <div class="head">
        <div>
          <div class="priority">{@character.priority} · {@character.tag}</div>
          <div class="name">{@character.name}</div>
        </div>
        <span class="pill">{@character.points}</span>
      </div>
      <div class="body-area">
        <div class="ability">{@character.ability}</div>
        <div class="win-cond"><strong>Win:</strong> {@character.win}</div>
        <%= if @taken? do %>
          <div class="game-character-taken">Chosen by {@taken_by}</div>
        <% end %>
      </div>
    </button>
    """
  end

  attr :room, :map, default: nil

  defp game_bar(assigns) do
    ~H"""
    <div class="app-bar game-nav">
      <.link navigate={~p"/lobby"} class="brand">
        <span class="glyph">T</span><span>Tricktakers</span>
      </.link>
      <nav>
        <.link navigate={if @room, do: ~p"/rooms/#{@room.code}", else: ~p"/lobby"}>
          Room
        </.link>
        <.link navigate={~p"/characters"}>Characters</.link>
      </nav>
    </div>
    """
  end

  attr :room, :map, required: true
  attr :player_session_id, :string, required: true
  attr :setup_error, :string, default: nil

  defp round_complete_phase(assigns) do
    assigns =
      assign(assigns, :summary, round_summary_state(assigns.room, assigns.player_session_id))

    ~H"""
    <section id="round-complete" class="game-setup page-wide">
      <header class="game-setup-header">
        <div>
          <div class="eyebrow">Round {@summary.round} complete</div>
          <h1 class="tt-heading-1 game-setup-title">Round results.</h1>
          <p class="body game-setup-copy">
            Crowns, points, and the next lead player are resolved after all 5 tricks.
          </p>
        </div>
        <div class="status-row game-setup-status">
          <span class="pill solid">{@summary.result_label}</span>
          <div class="sep"></div>
          <span class="mono muted">{@room.code}</span>
        </div>
      </header>

      <div class="game-setup-layout">
        <section class="panel game-character-setup-card">
          <div class="eyebrow">Outcome</div>
          <h2 class="tt-heading-2">{@summary.headline}</h2>
          <p class="body game-setup-copy">{@summary.detail}</p>

          <div class="game-picker-list">
            <%= for player <- @summary.players do %>
              <div class={["game-picker-row", player.you? && "you"]}>
                <div class="row gap-2">
                  <span class={["avatar", player.avatar_class]}>{player.initial}</span>
                  <div>
                    <div class="tt-heading-4">
                      {player.name}{if player.you?, do: " (you)", else: ""}
                    </div>
                    <div class="body-sm muted">{player.character.name} · {player.tricks} tricks</div>
                  </div>
                </div>
                <div class="row gap-2">
                  <span class="pill">{signed_points(player.points_delta)}</span>
                  <span class="pill solid">{player.points_after} pts</span>
                </div>
              </div>
            <% end %>
          </div>
        </section>

        <aside class="game-setup-sidebar">
          <div class="panel">
            <div class="eyebrow">Crowns</div>
            <div class="game-picker-list">
              <div class="game-picker-row">
                <span>Gold crown</span><span class="pill gold">{@summary.gold_crown_label}</span>
              </div>
              <div class="game-picker-row">
                <span>Black crowns</span><span class="pill">{@summary.black_crown_label}</span>
              </div>
            </div>
          </div>

          <div class="panel-soft">
            <div class="eyebrow">Next lead</div>
            <p class="body game-setup-note">{@summary.next_lead_label}</p>
          </div>

          <%= if @summary.can_continue? do %>
            <button
              id="continue-next-round"
              type="button"
              class="btn gold full"
              phx-click="continue_next_round"
            >
              Continue to round {@summary.next_round}
            </button>
          <% end %>

          <%= if @setup_error do %>
            <p class="body-sm game-selection-error">{@setup_error}</p>
          <% end %>
        </aside>
      </div>
    </section>
    """
  end

  attr :room, :map, required: true
  attr :player_session_id, :string, required: true
  attr :setup_error, :string, default: nil

  defp choosing_first_lead_phase(assigns) do
    assigns =
      assign(
        assigns,
        :lead_choice,
        first_lead_choice_state(assigns.room, assigns.player_session_id)
      )

    ~H"""
    <section id="choosing-first-lead" class="game-setup page-wide">
      <header class="game-setup-header">
        <div>
          <div class="eyebrow">Round {@lead_choice.round} · Lead token</div>
          <h1 class="tt-heading-1 game-setup-title">Choose the first lead.</h1>
          <p class="body game-setup-copy">
            Character setup is complete. The lead player token holder chooses who leads the first trick.
          </p>
        </div>
        <div class="status-row game-setup-status">
          <span class="pill solid">{@lead_choice.token_holder} holds the token</span>
          <div class="sep"></div>
          <span class="mono muted">{@room.code}</span>
        </div>
      </header>

      <div class="game-setup-layout">
        <section class="panel game-character-setup-card">
          <div class="eyebrow">First trick leader</div>
          <h2 class="tt-heading-2">
            <%= if @lead_choice.your_turn? do %>
              Pick any seated player.
            <% else %>
              Waiting for {@lead_choice.token_holder}.
            <% end %>
          </h2>
          <p class="body game-setup-copy">
            The chosen player starts trick 1. Normal trick winner rules decide later leads.
          </p>

          <div class="game-picker-list">
            <%= for player <- @lead_choice.players do %>
              <button
                id={"choose-first-lead-#{player.id}"}
                type="button"
                class={["game-picker-row", player.you? && "you"]}
                phx-click="choose_first_lead"
                phx-value-player={player.id}
                disabled={!@lead_choice.your_turn?}
              >
                <div class="row gap-2">
                  <span class={["avatar", player.avatar_class]}>{player.initial}</span>
                  <div>
                    <div class="tt-heading-4">
                      {player.name}{if player.you?, do: " (you)", else: ""}
                    </div>
                    <div class="body-sm muted">{player.character.name}</div>
                  </div>
                </div>
                <span class="pill">Lead trick 1</span>
              </button>
            <% end %>
          </div>

          <%= if @setup_error do %>
            <p class="body-sm game-selection-error">{@setup_error}</p>
          <% end %>
        </section>

        <aside class="game-setup-sidebar">
          <div class="panel-soft">
            <div class="eyebrow">Timing</div>
            <p class="body game-setup-note">
              This choice happens only after all character setup for the new round is finished.
            </p>
          </div>
        </aside>
      </div>
    </section>
    """
  end

  attr :room, :map, required: true
  attr :player_session_id, :string, required: true
  attr :play_error, :string, default: nil
  attr :revolt_ready?, :boolean, default: false

  defp active_table(assigns) do
    assigns =
      assigns
      |> assign(:table, table_state(assigns.room, assigns.player_session_id, assigns.play_error))

    ~H"""
    <section id="active-game-table" class="game-table-shell">
      <header class="game-status-bar">
        <div class="eyebrow">
          Round {@table.round} · Trick {@table.trick} of {@table.total_tricks}
        </div>
        <.progress_dots current={@table.trick} total={@table.total_tricks} />
        <div class="game-status-separator"></div>
        <div class="row gap-2 game-crown-ledger" aria-label="Crown ledger">
          <.crown />
          <.crown empty />
          <.crown empty />
          <span class="muted body-sm">/</span>
          <.crown black />
          <.crown black empty />
        </div>
        <div class="game-status-actions">
          <span class="pill red">Lead color · {@table.lead_color}</span>
          <span class="pill solid">{@table.active_player} leads</span>
          <.link navigate={~p"/characters"} class="btn ghost sm">Rules</.link>
          <.link navigate={~p"/rooms/#{@room.code}"} class="btn ghost sm">
            Room
          </.link>
        </div>
      </header>

      <div class="game-play-area">
        <div class="game-opponents" aria-label="Opponents">
          <%= for opponent <- @table.opponents do %>
            <div class="game-opponent">
              <.seat player={opponent} active={opponent.name == @table.active_player} />
              <.opponent_hand count={opponent.cards_left} />
            </div>
          <% end %>
        </div>

        <section class="game-center-stage" aria-label="Current trick">
          <div class="game-trick-meta">
            <span class="row gap-2">
              <span class={["game-lead-dot", lead_dot_class(@table.lead_suit)]}></span> {@table.lead_label} led
            </span>
            <span class="muted">·</span>
            <span class="muted">Must follow if able</span>
          </div>

          <div id="current-trick" class="game-trick">
            <%= for play <- @table.current_trick do %>
              <div class="game-trick-play" style={play.style}>
                <.playing_card card={play.card} />
              </div>
            <% end %>
            <%= if @table.waiting_for do %>
              <div class="game-trick-slot" style="transform: translate(140px, -20px) rotate(8deg);">
                {String.upcase(@table.waiting_for)}
              </div>
            <% end %>
          </div>

          <div class="row gap-3 center-x game-declare-row">
            <%= if @table.show_kakumei_button? do %>
              <button
                id="declare-kakumei"
                type="button"
                class="btn gold sm"
                phx-click="declare_kakumei"
                disabled={!@table.can_declare_kakumei? or @revolt_ready?}
              >
                <%= if @revolt_ready? do %>
                  Kakumei ready
                <% else %>
                  Declare Kakumei
                <% end %>
              </button>
            <% end %>
            <span class="muted body-sm">{@table.turn_copy}</span>
          </div>
        </section>

        <section class="game-player-panel" aria-label="Your hand">
          <div class="game-player-info">
            <.seat player={@table.you} you />
          </div>

          <div class="game-hand-zone">
            <div id="your-hand" class="game-hand hand">
              <%= for {card, index} <- Enum.with_index(@table.hand) do %>
                <button
                  type="button"
                  class={[
                    "pcard",
                    card_class(card),
                    "playable",
                    card[:disabled] && "disabled"
                  ]}
                  style={hand_card_style(index, length(@table.hand))}
                  phx-click={
                    if @table.hermit_discarding?, do: "discard_hermit_card", else: "play_card"
                  }
                  phx-value-card={card.id}
                  disabled={card[:disabled]}
                  aria-label={card_label(card)}
                >
                  <.card_face card={card} />
                </button>
              <% end %>
            </div>

            <%= if @table.play_error do %>
              <p class="body-sm game-selection-error">{@table.play_error}</p>
            <% end %>
          </div>

          <%= if @table.show_hermit_draw? do %>
            <button
              id="draw-hermit-card"
              type="button"
              class="btn ghost sm"
              phx-click="draw_hermit_card"
            >
              Draw then discard
            </button>
          <% end %>

          <aside class="game-turn-panel">
            <div class="row gap-3">
              <div class="game-timer">18</div>
              <div class="game-turn-copy">
                <div class="eyebrow">Your turn</div>
                <div class="body-sm muted">{@table.hand_prompt}</div>
              </div>
            </div>
            <div class="row gap-2 game-stat-pills">
              <span class="pill">Tricks won · {@table.you.tricks}</span>
              <span class="pill">Pts · {@table.you.points}</span>
            </div>
          </aside>
        </section>
      </div>
    </section>
    """
  end

  attr :current, :integer, required: true
  attr :total, :integer, required: true

  defp progress_dots(assigns) do
    ~H"""
    <span class="dots" aria-label={"Trick #{@current} of #{@total}"}>
      <%= for index <- 1..@total do %>
        <span class={["dot", index < @current && "done", index == @current && "now"]}></span>
      <% end %>
    </span>
    """
  end

  attr :black, :boolean, default: false
  attr :empty, :boolean, default: false

  defp crown(assigns) do
    ~H"""
    <span class={["crown", @black && "black", @empty && "empty"]}>♛</span>
    """
  end

  attr :player, :map, required: true
  attr :active, :boolean, default: false
  attr :you, :boolean, default: false

  defp seat(assigns) do
    ~H"""
    <div class={["seat", @active && "active", @you && "you"]}>
      <span class={["avatar", @player.avatar_class]}>{@player.initial}</span>
      <div class="meta">
        <div class="name">{@player.name}{if @you, do: " (you)", else: ""}</div>
        <div class="role">{@player.character} · {@player.priority}</div>
      </div>
      <div class="stat">
        <div class="label">Pts</div>
        {@player.points}
      </div>
    </div>
    """
  end

  attr :count, :integer, required: true

  defp opponent_hand(assigns) do
    ~H"""
    <div class="game-opponent-hand">
      <%= for _index <- 1..@count do %>
        <.playing_card card={%{kind: :back, size: :sm}} />
      <% end %>
    </div>
    """
  end

  attr :card, :map, required: true

  defp playing_card(assigns) do
    ~H"""
    <div class={["pcard", card_class(@card)]}>
      <.card_face card={@card} />
    </div>
    """
  end

  attr :card, :map, required: true

  defp card_face(assigns) do
    ~H"""
    <%= case @card.kind do %>
      <% :back -> %>
      <% :rare -> %>
        <div class="corner">
          <div class="num">R</div>
        </div>
        <div class="center">★</div>
        <div class="corner tr">
          <div class="num">R</div>
        </div>
      <% :white_flag -> %>
        <div class="corner">
          <div class="num">⚑</div>
        </div>
        <div class="center">⚑</div>
        <div class="corner tr">
          <div class="num">⚑</div>
        </div>
      <% _ -> %>
        <div class="corner">
          <div class="num">{@card.rank}</div>
          <div class="pip"></div>
        </div>
        <div class="center">{@card.rank}</div>
        <div class="corner tr">
          <div class="num">{@card.rank}</div>
          <div class="pip"></div>
        </div>
    <% end %>
    """
  end

  defp table_state(room, player_session_id, play_error) do
    game = room.game
    players = seat_players(room.players, player_session_id, game.character_picks || %{})
    you = Enum.find(players, &(&1.id == player_session_id)) || hd(players)

    opponents = Enum.reject(players, &(&1.name == you.name))
    current_player = Enum.find(players, &(&1.id == game.current_player)) || you
    lead_suit = Trick.lead_suit(game.current_trick || [])
    legal_card_ids = legal_card_ids(game, player_session_id)
    your_turn? = game.current_player == player_session_id
    resistance? = Map.get(game.character_picks || %{}, player_session_id) == "resistance"
    hermit? = Map.get(game.character_picks || %{}, player_session_id) == "hermit"

    hermit_discarding? =
      Map.has_key?(Map.get(game, :hermit_pending_draws, %{}), player_session_id)

    revolt_active? = get_in(game, [:revolt, :active_trick]) == game.trick

    %{
      round: game.round,
      trick: game.trick,
      total_tricks: 5,
      lead_suit: lead_suit,
      lead_label: lead_label(lead_suit),
      lead_color: lead_label(lead_suit),
      active_player: current_player.name,
      waiting_for: current_player.name,
      turn_copy:
        if(your_turn?, do: "Your turn to play.", else: "#{current_player.name} is thinking..."),
      show_kakumei_button?: resistance?,
      can_declare_kakumei?: can_declare_kakumei?(game, player_session_id),
      revolt_active?: revolt_active?,
      hermit_discarding?: hermit_discarding?,
      show_hermit_draw?: hermit? and your_turn? and not hermit_discarding?,
      hand_prompt: hand_prompt(your_turn?, lead_suit),
      play_error: play_error,
      you: you,
      opponents: opponents,
      current_trick: current_trick_state(game.current_trick || []),
      hand:
        room
        |> hand_for(player_session_id)
        |> Enum.map(fn card ->
          Map.put(
            card,
            :disabled,
            not your_turn? or (not hermit_discarding? and card.id not in legal_card_ids)
          )
        end)
    }
  end

  defp can_declare_kakumei?(game, player_session_id) do
    used_player_ids = get_in(game, [:revolt, :used_player_ids]) || []
    already_played? = Enum.any?(game.current_trick || [], &(&1.player_id == player_session_id))

    Map.get(game.character_picks || %{}, player_session_id) == "resistance" and
      player_session_id not in used_player_ids and
      get_in(game, [:revolt, :active_trick]) != game.trick and
      game.current_player == player_session_id and not already_played?
  end

  defp round_summary_state(room, player_session_id) do
    game = room.game
    result = game.round_result
    players = seat_players(room.players, player_session_id, game.character_picks || %{})
    winner_id = game.winner_id

    %{
      round: game.round,
      result_label: result_label(game.win_reason),
      headline: round_headline(room, winner_id, game.win_reason),
      detail: round_detail(room, result, game.win_reason),
      gold_crown_label:
        crown_player_label(room, result.gold_crown_winner_id, "No gold crown awarded"),
      black_crown_label: crown_players_label(room, result.black_crown_winner_ids),
      next_lead_label: next_lead_label(room, result.next_lead_player_id, winner_id),
      can_continue?: is_nil(winner_id) and game.round < max_rounds(room),
      next_round: game.round + 1,
      players:
        Enum.map(players, fn player ->
          %{
            name: player.name,
            initial: player.initial,
            avatar_class: player.avatar_class,
            character: character_by_id(Map.get(game.character_picks, player.id)),
            tricks: Map.get(game.trick_wins || %{}, player.id, 0),
            points_delta: Map.get(result.points_delta || %{}, player.id, 0),
            points_after:
              Map.get(
                result.points_after || %{},
                player.id,
                Map.get(game.points || %{}, player.id, 0)
              ),
            you?: player.id == player_session_id
          }
        end)
    }
  end

  defp first_lead_choice_state(room, player_session_id) do
    game = room.game
    players = seat_players(room.players, player_session_id, game.character_picks || %{})
    token_holder_id = game.lead_player_token_id

    %{
      round: game.round,
      token_holder: player_name(room, token_holder_id),
      your_turn?: token_holder_id == player_session_id,
      players:
        Enum.map(players, fn player ->
          %{
            id: player.id,
            name: player.name,
            initial: player.initial,
            avatar_class: player.avatar_class,
            character: character_by_id(Map.get(game.character_picks, player.id)),
            you?: player.id == player_session_id
          }
        end)
    }
  end

  defp result_label(:character), do: "Character victory"
  defp result_label(:crown), do: "Crown victory"
  defp result_label(:points), do: "Final points victory"
  defp result_label(_reason), do: "Round complete"

  defp round_headline(_room, nil, _reason), do: "No immediate winner."

  defp round_headline(room, winner_id, :character),
    do: "#{player_name(room, winner_id)} wins by character condition."

  defp round_headline(room, winner_id, :crown),
    do: "#{player_name(room, winner_id)} wins by crowns."

  defp round_headline(room, winner_id, :points),
    do: "#{player_name(room, winner_id)} wins by final points."

  defp round_headline(room, winner_id, _reason), do: "#{player_name(room, winner_id)} wins."

  defp round_detail(_room, %{character_winner_id: winner_id}, _reason) when is_binary(winner_id),
    do: "Character win conditions are checked before crowns and points."

  defp round_detail(_room, result, :points) do
    if final_points_tied?(result.points_after || %{}) do
      "Final points were tied, so character precedence broke the tie."
    else
      "No character or crown victory occurred, so final points decided the game."
    end
  end

  defp round_detail(_room, _result, _reason), do: "Crowns and point changes have been applied."

  defp final_points_tied?(points) do
    {_max_points, count} =
      Enum.reduce(points, {nil, 0}, fn {_player_id, points}, {max_points, count} ->
        cond do
          is_nil(max_points) or points > max_points -> {points, 1}
          points == max_points -> {max_points, count + 1}
          true -> {max_points, count}
        end
      end)

    count > 1
  end

  defp crown_player_label(_room, nil, fallback), do: fallback
  defp crown_player_label(room, player_id, _fallback), do: player_name(room, player_id)

  defp crown_players_label(_room, []), do: "No black crowns awarded"

  defp crown_players_label(room, player_ids) do
    player_ids |> Enum.map(&player_name(room, &1)) |> Enum.join(", ")
  end

  defp next_lead_label(_room, _next_lead_player_id, winner_id) when is_binary(winner_id),
    do: "Game complete."

  defp next_lead_label(room, player_id, _winner_id) when is_binary(player_id),
    do: "#{player_name(room, player_id)} gets the lead player token."

  defp next_lead_label(_room, _player_id, _winner_id), do: "Next lead pending."

  defp signed_points(points) when points > 0, do: "+#{points} pts"
  defp signed_points(points), do: "#{points} pts"

  defp max_rounds(%{max_players: 2}), do: 5
  defp max_rounds(_room), do: 3

  defp legal_card_ids(game, player_session_id) do
    hand = get_in(game, [:hands, player_session_id]) || []

    if game.current_player == player_session_id do
      Trick.legal_cards(hand, game.current_trick || [])
      |> Enum.map(& &1.id)
    else
      []
    end
  end

  defp current_trick_state(plays) do
    plays
    |> Enum.with_index()
    |> Enum.map(fn {play, index} ->
      %{card: play.card, player_id: play.player_id, style: trick_card_style(index)}
    end)
  end

  defp trick_card_style(0), do: "transform: translate(-130px, -10px) rotate(-6deg);"
  defp trick_card_style(1), do: "transform: translate(0, -30px) rotate(4deg);"
  defp trick_card_style(2), do: "transform: translate(130px, -10px) rotate(8deg);"
  defp trick_card_style(3), do: "transform: translate(-50px, 70px) rotate(-3deg);"
  defp trick_card_style(_index), do: "transform: translate(70px, 70px) rotate(5deg);"

  defp lead_label(nil), do: "No suit"
  defp lead_label(suit), do: suit |> Atom.to_string() |> String.capitalize()

  defp lead_dot_class(:red), do: "red"
  defp lead_dot_class(_suit), do: nil

  defp hand_prompt(false, _lead_suit), do: "Waiting for your turn."
  defp hand_prompt(true, nil), do: "Lead any card."
  defp hand_prompt(true, suit), do: "Follow #{lead_label(suit)} if able."

  defp seat_players(players, _player_session_id, character_picks) do
    roster = fallback_roster()

    players
    |> Enum.with_index()
    |> Enum.map(fn {player, index} ->
      fallback = Enum.at(roster, index)
      character = character_by_id(Map.get(character_picks, player.id)) || fallback

      fallback
      |> Map.put(:character, character.name)
      |> Map.put(:priority, character.priority)
      |> Map.put(:id, player.id)
      |> Map.put(:name, player.name)
      |> Map.put(:initial, initial(player.name))
      |> Map.put(:cards_left, 3)
    end)
  end

  defp character_selection_state(room, player_session_id) do
    game = room.game
    picks = game.character_picks || %{}
    characters = characters_for_mode(room.mode)
    current_picker = Enum.at(game.character_order, game.current_picker_index)

    taken_by =
      Map.new(picks, fn {player_id, character_id} ->
        {character_id, player_name(room, player_id)}
      end)

    players = seat_players(room.players, player_session_id, picks)

    %{
      round: game.round,
      rounds: if(room.max_players == 2, do: 5, else: 3),
      current_picker: player_name(room, current_picker),
      current_pick_number: min(map_size(picks) + 1, length(game.character_order)),
      total_picks: length(game.character_order),
      available_count: length(characters),
      characters: characters,
      taken_by: taken_by,
      your_turn?: current_picker == player_session_id,
      hand_preview: hand_for(room, player_session_id, :sm),
      pickers:
        Enum.map(game.character_order, fn player_id ->
          character = character_by_id(Map.get(picks, player_id))
          player = Enum.find(players, &(&1.id == player_id))
          name = player_name(room, player_id)

          %{
            name: name,
            initial: initial(name),
            avatar_class: player && player.avatar_class,
            character: character,
            current?: player_id == current_picker,
            you?: player_id == player_session_id
          }
        end)
    }
  end

  defp character_setup_state(room, player_session_id) do
    game = room.game
    setup_done = game.character_setup_done || %{}
    players = seat_players(room.players, player_session_id, game.character_picks || %{})
    current_player = Enum.at(game.character_setup_order, game.current_setup_index)
    current_character = character_by_id(Map.get(game.character_picks, current_player))

    %{
      round: game.round,
      rounds: if(room.max_players == 2, do: 5, else: 3),
      current_player: player_name(room, current_player),
      current_character: current_character,
      current_setup_number: min(map_size(setup_done) + 1, length(game.character_setup_order)),
      total_setups: length(game.character_setup_order),
      your_turn?: current_player == player_session_id,
      hand_preview: hand_for(room, player_session_id, :sm),
      gambler_redraw_count:
        game |> Map.get(:gambler_redraws, %{}) |> Map.get(player_session_id, 0),
      players:
        Enum.map(game.character_setup_order, fn player_id ->
          player = Enum.find(players, &(&1.id == player_id))
          name = player_name(room, player_id)

          %{
            name: name,
            initial: initial(name),
            avatar_class: player && player.avatar_class,
            character: character_by_id(Map.get(game.character_picks, player_id)),
            current?: player_id == current_player,
            done?: Map.has_key?(setup_done, player_id),
            you?: player_id == player_session_id
          }
        end)
    }
  end

  defp game_phase(%{game: %{phase: phase}}), do: phase
  defp game_phase(_room), do: :playing

  defp player_in_room?(room, player_session_id),
    do: RoomRegistry.player_in_room?(room, player_session_id)

  defp player_name(room, player_session_id),
    do: RoomRegistry.player_name(room, player_session_id) || "Unknown"

  defp hand_for(room, player_session_id, size \\ nil) do
    room
    |> get_in([:game, :hands, player_session_id])
    |> case do
      nil -> []
      hand -> Enum.map(hand, &maybe_put_size(&1, size))
    end
  end

  defp maybe_put_size(card, nil), do: card
  defp maybe_put_size(card, size), do: Map.put(card, :size, size)

  defp setup_state_for(room, player_session_id, setup_state) do
    game = room && room.game

    current_player =
      game && Enum.at(game.character_setup_order || [], game.current_setup_index || 0)

    character_id = game && Map.get(game.character_picks || %{}, current_player)

    redraw_count =
      game |> Kernel.||(%{}) |> Map.get(:gambler_redraws, %{}) |> Map.get(player_session_id, 0)

    SetupState.for_character(
      character_id,
      hand_for(room, player_session_id, :sm),
      redraw_count,
      setup_state
    )
  end

  defp selected_black_crown_card_ids(room, player_session_id, selected_card_ids) do
    hand_ids = room |> hand_for(player_session_id) |> Enum.map(& &1.id) |> MapSet.new()
    Enum.filter(selected_card_ids, &MapSet.member?(hand_ids, &1))
  end

  defp black_crown_redraw_state(room, player_session_id, selected_card_ids) do
    game = room.game
    eligible = Map.get(game, :black_crown_redraw_eligible, [])
    done = Map.get(game, :black_crown_redraw_done, %{})
    waiting_player_ids = Enum.reject(eligible, &Map.has_key?(done, &1))
    crowns_left = get_in(game, [:crowns, player_session_id, :black]) || 0

    %{
      your_turn?: player_session_id in waiting_player_ids,
      crowns_left: crowns_left,
      selected_count: length(selected_card_ids),
      hand: hand_for(room, player_session_id, :sm),
      waiting_label: waiting_player_names(room, waiting_player_ids)
    }
  end

  defp waiting_player_names(_room, []), do: "All eligible players are done."

  defp waiting_player_names(room, player_ids) do
    names = Enum.map(player_ids, &player_name(room, &1))

    case names do
      [name] -> "Waiting for #{name}."
      _ -> "Waiting for #{Enum.join(names, ", ")}."
    end
  end

  defp maybe_auto_complete_setup(socket) do
    room = socket.assigns.room
    player_session_id = socket.assigns.player_session_id

    if auto_complete_setup?(room, player_session_id) do
      case RoomRegistry.complete_character_setup(room.code, player_session_id, %{
             "notes" => "auto"
           }) do
        {:ok, room} ->
          assign(socket,
            room: room,
            setup_state: setup_state_for(room, player_session_id, socket.assigns.setup_state),
            setup_error: nil
          )

        {:error, reason} ->
          assign(socket, :setup_error, reason)
      end
    else
      socket
    end
  end

  defp auto_complete_setup?(%{game: %{phase: :character_setup} = game}, player_session_id) do
    current_player_id = Enum.at(game.character_setup_order || [], game.current_setup_index || 0)
    character_id = Map.get(game.character_picks || %{}, current_player_id)

    current_player_id == player_session_id and
      not Map.has_key?(game.character_setup_done || %{}, player_session_id) and
      not setup_requires_input?(character_id)
  end

  defp auto_complete_setup?(_room, _player_session_id), do: false

  defp setup_requires_input?(character_id), do: character_id in ["king", "gambler"]

  defp characters_for_mode("Advanced"), do: character_roster()
  defp characters_for_mode(_mode), do: Enum.filter(character_roster(), &(&1.group == :basic))

  defp character_by_id(nil), do: nil
  defp character_by_id(id), do: Enum.find(character_roster(), &(&1.id == id))

  defp current_setup_character_id(%{
         game: %{
           character_setup_order: order,
           current_setup_index: index,
           character_picks: picks
         }
       }) do
    current_player = Enum.at(order || [], index || 0)
    Map.get(picks || %{}, current_player)
  end

  defp current_setup_character_id(_room), do: nil

  defp character_roster do
    [
      %{
        id: "king",
        name: "King",
        priority: "1A",
        tag: "Trick winner",
        group: :basic,
        ability: "Adds the King's Exclusive Rare, then discards one card to balance the hand.",
        win: "Win all 5 tricks",
        points: "Tricks"
      },
      %{
        id: "gambler",
        name: "Gambler",
        priority: "2A",
        tag: "Bid + bet",
        group: :basic,
        ability:
          "Declares a trick bid, can redraw up to twice, and wagers points on hitting the bid.",
        win: "Hit bid or win all 5 tricks",
        points: "Bid"
      },
      %{
        id: "resistance",
        name: "Resistance",
        priority: "3A",
        tag: "Revolt",
        group: :basic,
        ability:
          "May trigger one Revolt Trick where lowest strength wins and normal advantages invert.",
        win: "Win Revolt with Black",
        points: "Revolt"
      },
      %{
        id: "hermit",
        name: "Hermit",
        priority: "4A",
        tag: "Dexterous hand",
        group: :basic,
        ability: "Draws and discards before playing; White Flag can beat Rare outside Revolt.",
        win: "Win all 5 tricks",
        points: "Rare beats"
      },
      %{
        id: "berserker",
        name: "Berserker",
        priority: "5A",
        tag: "Fierce uplift",
        group: :basic,
        ability:
          "Swaps into the Berserker deck; Berserker beats Rare, but any 1 beats Berserker.",
        win: "Win 0 tricks",
        points: "Crowns"
      },
      %{
        id: "adventurer",
        name: "Adventurer",
        priority: "3B",
        tag: "Items",
        group: :advanced,
        ability: "Equips items and turns won tricks into new equipment slots.",
        win: "Score through item timing",
        points: "Items"
      },
      %{
        id: "collector",
        name: "Collector",
        priority: "4B",
        tag: "Set collection",
        group: :advanced,
        ability: "Reserves cards from tricks and scores poker-style combinations at round end.",
        win: "Build the best sets",
        points: "Sets"
      },
      %{
        id: "ruler",
        name: "Ruler",
        priority: "5B",
        tag: "Tasks",
        group: :advanced,
        ability: "Gives task cards to opponents and scores from completed table objectives.",
        win: "Everyone completes tasks",
        points: "Tasks"
      }
    ]
  end

  defp fallback_roster do
    [
      %{name: "King", priority: "1A", points: 120, tricks: 1, avatar_class: "a4"},
      %{name: "Hermit", priority: "4A", points: 90, tricks: 2, avatar_class: "a1"},
      %{name: "Berserker", priority: "5A", points: 60, tricks: 1, avatar_class: "a2"},
      %{name: "Gambler", priority: "2A", points: 30, tricks: 0, avatar_class: "a3"},
      %{name: "Resistance", priority: "3A", points: 30, tricks: 0, avatar_class: "a5"}
    ]
  end

  defp character_button_label(character, nil, true), do: "#{character.name}; wait for your turn"
  defp character_button_label(character, nil, false), do: "Choose #{character.name}"

  defp character_button_label(character, taken_by, _disabled),
    do: "#{character.name}; chosen by #{taken_by}"

  defp card_class(card) do
    [
      size_class(card),
      kind_class(card)
    ]
  end

  defp size_class(%{size: :sm}), do: "size-sm"
  defp size_class(%{size: :lg}), do: "size-lg"
  defp size_class(_card), do: nil

  defp kind_class(%{kind: :back}), do: "back"
  defp kind_class(%{kind: :rare}), do: "rare"
  defp kind_class(%{kind: :white_flag}), do: "white-flag"
  defp kind_class(%{suit: suit}), do: to_string(suit)
  defp kind_class(_card), do: nil

  defp hand_card_style(index, count) do
    spread = min(380, count * 70)
    step = if count > 1, do: spread / (count - 1), else: 0
    t = if count > 1, do: index / (count - 1) - 0.5, else: 0
    x = t * spread
    rotation = t * 8
    y = abs(t) * 6

    "left: 50%; margin-left: -48px; transform: translateX(#{x}px) translateY(#{y}px) rotate(#{rotation}deg); --hand-x: #{x}px; --hand-y: #{y}px; --hand-rot: #{rotation}deg; --hand-step: #{step}px;"
  end

  defp card_label(%{kind: :rare}), do: "Rare card"
  defp card_label(%{kind: :white_flag}), do: "White Flag card"
  defp card_label(%{kind: :back}), do: "Face-down card"

  defp card_label(%{suit: suit, rank: rank}),
    do: "#{String.capitalize(to_string(suit))} #{rank}"

  defp initial(name) do
    name
    |> to_string()
    |> String.trim()
    |> String.first()
    |> case do
      nil -> "?"
      letter -> String.upcase(letter)
    end
  end
end
