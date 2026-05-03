defmodule TricktakersWebWeb.GameLive do
  use TricktakersWebWeb, :live_view

  alias TricktakersWeb.Game.SetupState
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
                <% _phase -> %>
                  <.active_table room={@room} player_session_id={@player_session_id} />
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

  defp setup_card_role("toggle_gambler_card"), do: "checkbox"
  defp setup_card_role(_event), do: "radio"

  defp setup_hand_hint("toggle_gambler_card", _selected_card_id, []),
    do: "Select any cards you want to discard."

  defp setup_hand_hint("toggle_gambler_card", _selected_card_id, selected_card_ids),
    do: "#{length(selected_card_ids)} selected; redraw will replace that many cards."

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

  defp active_table(assigns) do
    assigns =
      assigns
      |> assign(:table, table_state(assigns.room, assigns.player_session_id))

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
              <span class="game-lead-dot red"></span> {@table.lead_color} led
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
            <div class="game-trick-slot" style="transform: translate(140px, -20px) rotate(8deg);">
              {String.upcase(@table.waiting_for)}
            </div>
          </div>

          <div class="row gap-3 center-x game-declare-row">
            <button class="btn gold sm" disabled>Declare Kakumei</button>
            <span class="muted body-sm">{@table.waiting_for} is thinking...</span>
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
                  disabled={card[:disabled]}
                  aria-label={card_label(card)}
                >
                  <.card_face card={card} />
                </button>
              <% end %>
            </div>

            <div class="row gap-3 center-x">
              <button class="btn ghost sm" type="button">Cancel</button>
              <button class="btn" type="button">Play card</button>
            </div>
          </div>

          <aside class="game-turn-panel">
            <div class="row gap-3">
              <div class="game-timer">18</div>
              <div class="game-turn-copy">
                <div class="eyebrow">Your turn</div>
                <div class="body-sm muted">Pick any Red, or override.</div>
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

  defp table_state(room, player_session_id) do
    players = seat_players(room.players, player_session_id, room.game.character_picks || %{})
    you = Enum.find(players, &(&1.id == player_session_id)) || hd(players)

    opponents = Enum.reject(players, &(&1.name == you.name))

    %{
      round: (room.game && room.game.round) || 1,
      trick: max((room.game && room.game.trick) || 1, 3),
      total_tricks: 5,
      lead_color: "Red",
      active_player: List.first(opponents, you).name,
      waiting_for: (Enum.at(opponents, 1) || you).name,
      you: you,
      opponents: opponents,
      current_trick: [
        %{
          player: List.first(opponents, you).name,
          card: %{id: "preview-red-5", kind: :number, suit: :red, rank: 5},
          style: "transform: translate(-130px, -10px) rotate(-6deg);"
        },
        %{
          player: (Enum.at(opponents, 2) || you).name,
          card: %{id: "preview-red-2", kind: :number, suit: :red, rank: 2},
          style: "transform: translate(0, -30px) rotate(4deg);"
        }
      ],
      hand: hand_for(room, player_session_id)
    }
  end

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
