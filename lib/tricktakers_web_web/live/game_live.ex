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
      <div class="app game-app">
        <.game_bar room={@room} player_name={@player_name} />

        <main>
          <%= if is_nil(@room) do %>
            <div class="page panel">
              <h1 class="h-2">Game not found</h1>
              <.link navigate={~p"/lobby"} class="btn" style="margin-top: 12px;">Back to lobby</.link>
            </div>
          <% else %>
            <.active_table room={@room} player_name={@player_name} />
          <% end %>
        </main>
      </div>
    </Layouts.app>
    """
  end

  attr :room, :map, default: nil
  attr :player_name, :string, required: true

  defp game_bar(assigns) do
    ~H"""
    <div class="app-bar game-nav">
      <.link navigate={~p"/lobby"} class="brand">
        <span class="glyph">T</span><span>Tricktakers</span>
      </.link>
      <nav>
        <.link navigate={
          if @room, do: ~p"/rooms/#{@room.code}?name=#{@player_name}", else: ~p"/lobby"
        }>
          Room
        </.link>
        <.link navigate={~p"/characters"}>Characters</.link>
      </nav>
      <%= if @room && @player_name != "" do %>
        <div class="you">
          <span>You're playing as <strong>{@player_name}</strong></span>
          <span class="avatar a4">{initial(@player_name)}</span>
        </div>
      <% end %>
    </div>
    """
  end

  attr :room, :map, required: true
  attr :player_name, :string, required: true

  defp active_table(assigns) do
    assigns =
      assigns
      |> assign(:table, table_state(assigns.room, assigns.player_name))

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
          <.link navigate={~p"/rooms/#{@room.code}?name=#{@player_name}"} class="btn ghost sm">
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
          <div class="num">{@card.value}</div>
          <div class="pip"></div>
        </div>
        <div class="center">{@card.value}</div>
        <div class="corner tr">
          <div class="num">{@card.value}</div>
          <div class="pip"></div>
        </div>
    <% end %>
    """
  end

  defp table_state(room, player_name) do
    players = seat_players(room.players, player_name)

    you =
      Enum.find(players, &(String.downcase(&1.name) == String.downcase(player_name || ""))) ||
        hd(players)

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
          card: %{kind: :number, suit: :red, value: 5},
          style: "transform: translate(-130px, -10px) rotate(-6deg);"
        },
        %{
          player: (Enum.at(opponents, 2) || you).name,
          card: %{kind: :number, suit: :red, value: 2},
          style: "transform: translate(0, -30px) rotate(4deg);"
        }
      ],
      hand: [
        %{kind: :number, suit: :red, value: 9},
        %{kind: :number, suit: :red, value: 4},
        %{kind: :number, suit: :blue, value: 2, disabled: true},
        %{kind: :number, suit: :black, value: 1, disabled: true},
        %{kind: :rare}
      ]
    }
  end

  defp seat_players(players, player_name) do
    names =
      ([player_name | players] ++ ["akari", "ryan_c", "fumi"])
      |> Enum.map(&String.trim(to_string(&1 || "")))
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()
      |> Enum.take(4)

    roster = [
      %{character: "King", priority: "1A", points: 120, tricks: 1, avatar_class: "a4"},
      %{character: "Hermit", priority: "4A", points: 90, tricks: 2, avatar_class: "a1"},
      %{character: "Berserker", priority: "5A", points: 60, tricks: 1, avatar_class: "a2"},
      %{character: "Gambler", priority: "2A", points: 30, tricks: 0, avatar_class: "a3"}
    ]

    names
    |> Enum.with_index()
    |> Enum.map(fn {name, index} ->
      roster_entry = Enum.at(roster, index)

      roster_entry
      |> Map.put(:name, name)
      |> Map.put(:initial, initial(name))
      |> Map.put(:cards_left, 3)
    end)
  end

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

  defp card_label(%{suit: suit, value: value}),
    do: "#{String.capitalize(to_string(suit))} #{value}"

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
