defmodule TricktakersWeb.RoomRegistry do
  use GenServer

  alias TricktakersWeb.Game.Deck
  alias TricktakersWeb.Game.Round
  alias TricktakersWeb.Game.Trick

  @topic "rooms"

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def list_rooms do
    GenServer.call(__MODULE__, :list_rooms)
  end

  def get_room(code) do
    GenServer.call(__MODULE__, {:get_room, code})
  end

  def create_room(attrs, player_session_id) do
    GenServer.call(__MODULE__, {:create_room, attrs, player_session_id})
  end

  def join_room(code, player_session_id, player_name) do
    GenServer.call(__MODULE__, {:join_room, code, player_session_id, player_name})
  end

  def start_game(code, player_session_id) do
    GenServer.call(__MODULE__, {:start_game, code, player_session_id})
  end

  def choose_character(code, player_session_id, character_id) do
    GenServer.call(__MODULE__, {:choose_character, code, player_session_id, character_id})
  end

  def complete_character_setup(code, player_session_id, attrs) do
    GenServer.call(__MODULE__, {:complete_character_setup, code, player_session_id, attrs})
  end

  def redraw_gambler_hand(code, player_session_id, card_ids) do
    GenServer.call(__MODULE__, {:redraw_gambler_hand, code, player_session_id, card_ids})
  end

  def play_card(code, player_session_id, card_id) do
    GenServer.call(__MODULE__, {:play_card, code, player_session_id, card_id})
  end

  def continue_next_round(code, player_session_id) do
    GenServer.call(__MODULE__, {:continue_next_round, code, player_session_id})
  end

  def choose_first_lead(code, player_session_id, chosen_player_id) do
    GenServer.call(__MODULE__, {:choose_first_lead, code, player_session_id, chosen_player_id})
  end

  def player_name(room, player_session_id) do
    room
    |> player_for_session(player_session_id)
    |> case do
      nil -> nil
      player -> player.name
    end
  end

  def player_in_room?(room, player_session_id),
    do: not is_nil(player_for_session(room, player_session_id))

  def player_names(room), do: Enum.map(room.players, & &1.name)

  def subscribe_rooms, do: Phoenix.PubSub.subscribe(TricktakersWeb.PubSub, @topic)
  def subscribe_room(code), do: Phoenix.PubSub.subscribe(TricktakersWeb.PubSub, room_topic(code))

  @impl true
  def init(_state), do: {:ok, %{rooms: %{}}}

  @impl true
  def handle_call(:list_rooms, _from, state) do
    rooms =
      state.rooms
      |> Map.values()
      |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})

    {:reply, rooms, state}
  end

  def handle_call({:get_room, code}, _from, state) do
    {:reply, Map.get(state.rooms, String.upcase(code || "")), state}
  end

  def handle_call({:create_room, attrs, player_session_id}, _from, state) do
    with {:ok, player_name} <- validate_name(attrs["player_name"]),
         {:ok, valid_session_id} <- validate_session_id(player_session_id),
         {:ok, room_name} <- validate_room_name(attrs["room_name"]),
         {:ok, max_players} <- validate_max_players(attrs["max_players"]),
         {:ok, mode} <- validate_mode(attrs["mode"]) do
      code = unique_code(state.rooms)
      now = DateTime.utc_now()

      room = %{
        code: code,
        name: room_name,
        host_id: valid_session_id,
        host: player_name,
        max_players: max_players,
        mode: mode,
        status: :waiting,
        players: [%{id: valid_session_id, name: player_name}],
        inserted_at: now,
        updated_at: now,
        game: nil
      }

      new_state = put_in(state, [:rooms, code], room)
      broadcast_rooms(new_state)
      broadcast_room(room)
      {:reply, {:ok, room}, new_state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:join_room, code, player_session_id, player_name}, _from, state) do
    room = Map.get(state.rooms, String.upcase(code || ""))

    with {:ok, found_room} <- fetch_room(room),
         {:ok, valid_session_id} <- validate_session_id(player_session_id),
         {:ok, valid_name} <- validate_name(player_name),
         :ok <- ensure_joinable(found_room, valid_session_id),
         :ok <- ensure_capacity(found_room, valid_session_id) do
      players =
        if player_in_room?(found_room, valid_session_id) do
          found_room.players
        else
          found_room.players ++ [%{id: valid_session_id, name: valid_name}]
        end

      updated_room = %{found_room | players: players, updated_at: DateTime.utc_now()}
      new_state = put_in(state, [:rooms, updated_room.code], updated_room)
      broadcast_rooms(new_state)
      broadcast_room(updated_room)
      {:reply, {:ok, updated_room}, new_state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:start_game, code, player_session_id}, _from, state) do
    room = Map.get(state.rooms, String.upcase(code || ""))

    with {:ok, found_room} <- fetch_room(room),
         {:ok, valid_session_id} <- validate_session_id(player_session_id),
         :ok <- ensure_host(found_room, valid_session_id),
         :ok <- ensure_minimum_players(found_room) do
      player_ids = Enum.map(found_room.players, & &1.id)
      {hands, draw_pile} = Deck.deal_with_draw_pile(player_ids)

      game = %{
        started_at: DateTime.utc_now(),
        phase: :character_selection,
        round: 1,
        trick: 1,
        lead: hd(player_ids),
        current_player: hd(player_ids),
        current_trick: [],
        completed_tricks: [],
        trick_wins: %{},
        crowns: Map.new(player_ids, &{&1, %{gold: 0, black: 0}}),
        lead_player_token_id: hd(player_ids),
        character_order: player_ids,
        points: Map.new(player_ids, &{&1, 30}),
        hands: hands,
        draw_pile: draw_pile,
        discards: [],
        gambler_redraws: %{},
        character_picks: %{},
        current_picker_index: 0,
        character_setup_order: [],
        character_setup_done: %{},
        current_setup_index: 0
      }

      updated_room =
        found_room
        |> Map.put(:status, :in_progress)
        |> Map.put(:game, game)
        |> Map.put(:updated_at, DateTime.utc_now())

      new_state = put_in(state, [:rooms, updated_room.code], updated_room)
      broadcast_rooms(new_state)
      broadcast_room(updated_room)
      broadcast_game_started(updated_room)
      {:reply, {:ok, updated_room}, new_state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:choose_character, code, player_session_id, character_id}, _from, state) do
    room = Map.get(state.rooms, String.upcase(code || ""))

    with {:ok, found_room} <- fetch_room(room),
         {:ok, valid_session_id} <- validate_session_id(player_session_id),
         {:ok, game} <- fetch_game(found_room),
         :ok <- ensure_setup_phase(game),
         :ok <- ensure_current_picker(game, valid_session_id),
         {:ok, valid_character_id} <- validate_character_id(found_room.mode, character_id),
         :ok <- ensure_character_available(game, valid_character_id) do
      picks = Map.put(game.character_picks, valid_session_id, valid_character_id)
      all_picked? = map_size(picks) == length(game.character_order)

      game =
        if all_picked? do
          setup_order = character_setup_order(game.character_order, picks)

          game
          |> Map.put(:character_picks, picks)
          |> Map.put(:phase, :character_setup)
          |> Map.put(:character_setup_order, setup_order)
          |> Map.put(:character_setup_done, %{})
          |> Map.put(:current_setup_index, 0)
          |> apply_setup_start_bonuses()
        else
          game
          |> Map.put(:character_picks, picks)
          |> Map.put(:current_picker_index, next_picker_index(game, picks))
        end

      updated_room =
        found_room
        |> Map.put(:game, game)
        |> Map.put(:updated_at, DateTime.utc_now())

      new_state = put_in(state, [:rooms, updated_room.code], updated_room)
      broadcast_rooms(new_state)
      broadcast_room(updated_room)
      {:reply, {:ok, updated_room}, new_state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:complete_character_setup, code, player_session_id, attrs}, _from, state) do
    room = Map.get(state.rooms, String.upcase(code || ""))

    with {:ok, found_room} <- fetch_room(room),
         {:ok, valid_session_id} <- validate_session_id(player_session_id),
         {:ok, game} <- fetch_game(found_room),
         :ok <- ensure_character_setup_phase(game),
         :ok <- ensure_current_setup_player(game, valid_session_id),
         setup_attrs = normalize_setup_attrs(attrs),
         {:ok, game} <- apply_character_setup(game, valid_session_id, setup_attrs) do
      setup_done =
        Map.put(game.character_setup_done, valid_session_id, setup_attrs)

      all_setup? = map_size(setup_done) == length(game.character_setup_order)

      game =
        game
        |> Map.put(:character_setup_done, setup_done)
        |> Map.put(:current_setup_index, next_setup_index(game, setup_done))
        |> start_playing_if_ready(all_setup?)

      updated_room =
        found_room
        |> Map.put(:game, game)
        |> Map.put(:updated_at, DateTime.utc_now())

      new_state = put_in(state, [:rooms, updated_room.code], updated_room)
      broadcast_rooms(new_state)
      broadcast_room(updated_room)
      {:reply, {:ok, updated_room}, new_state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:redraw_gambler_hand, code, player_session_id, card_ids}, _from, state) do
    room = Map.get(state.rooms, String.upcase(code || ""))

    with {:ok, found_room} <- fetch_room(room),
         {:ok, valid_session_id} <- validate_session_id(player_session_id),
         {:ok, game} <- fetch_game(found_room),
         :ok <- ensure_character_setup_phase(game),
         :ok <- ensure_current_setup_player(game, valid_session_id),
         :ok <- ensure_current_character(game, valid_session_id, "gambler"),
         {:ok, discard_ids} <- validate_redraw_card_ids(game, valid_session_id, card_ids),
         :ok <- ensure_gambler_redraw_available(game, valid_session_id),
         {:ok, game} <- redraw_hand(game, valid_session_id, discard_ids) do
      updated_room =
        found_room
        |> Map.put(:game, game)
        |> Map.put(:updated_at, DateTime.utc_now())

      new_state = put_in(state, [:rooms, updated_room.code], updated_room)
      broadcast_rooms(new_state)
      broadcast_room(updated_room)
      {:reply, {:ok, updated_room}, new_state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:play_card, code, player_session_id, card_id}, _from, state) do
    room = Map.get(state.rooms, String.upcase(code || ""))

    with {:ok, found_room} <- fetch_room(room),
         {:ok, valid_session_id} <- validate_session_id(player_session_id),
         {:ok, game} <- fetch_game(found_room),
         :ok <- ensure_playing_phase(game),
         :ok <- ensure_current_player(game, valid_session_id),
         {:ok, card} <- fetch_hand_card(game, valid_session_id, card_id),
         :ok <- ensure_legal_play(game, valid_session_id, card),
         {:ok, game} <- play_card_in_game(game, valid_session_id, card) do
      updated_room =
        found_room
        |> Map.put(:game, game)
        |> Map.put(:updated_at, DateTime.utc_now())

      new_state = put_in(state, [:rooms, updated_room.code], updated_room)
      broadcast_rooms(new_state)
      broadcast_room(updated_room)
      {:reply, {:ok, updated_room}, new_state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:continue_next_round, code, player_session_id}, _from, state) do
    room = Map.get(state.rooms, String.upcase(code || ""))

    with {:ok, found_room} <- fetch_room(room),
         {:ok, valid_session_id} <- validate_session_id(player_session_id),
         {:ok, game} <- fetch_game(found_room),
         :ok <- ensure_round_complete_phase(game),
         :ok <- ensure_no_winner(game),
         :ok <- ensure_round_remaining(found_room, game),
         :ok <- ensure_player_in_room(found_room, valid_session_id),
         {:ok, game} <- start_next_round(found_room, game) do
      updated_room =
        found_room
        |> Map.put(:game, game)
        |> Map.put(:updated_at, DateTime.utc_now())

      new_state = put_in(state, [:rooms, updated_room.code], updated_room)
      broadcast_rooms(new_state)
      broadcast_room(updated_room)
      {:reply, {:ok, updated_room}, new_state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:choose_first_lead, code, player_session_id, chosen_player_id}, _from, state) do
    room = Map.get(state.rooms, String.upcase(code || ""))

    with {:ok, found_room} <- fetch_room(room),
         {:ok, valid_session_id} <- validate_session_id(player_session_id),
         {:ok, valid_chosen_player_id} <- validate_session_id(chosen_player_id),
         {:ok, game} <- fetch_game(found_room),
         :ok <- ensure_choose_first_lead_phase(game),
         :ok <- ensure_lead_token_holder(game, valid_session_id),
         :ok <- ensure_player_in_round(game, valid_chosen_player_id) do
      game =
        game
        |> Map.put(:phase, :playing)
        |> Map.put(:lead, valid_chosen_player_id)
        |> Map.put(:current_player, valid_chosen_player_id)
        |> Map.put(:current_trick, [])

      updated_room =
        found_room
        |> Map.put(:game, game)
        |> Map.put(:updated_at, DateTime.utc_now())

      new_state = put_in(state, [:rooms, updated_room.code], updated_room)
      broadcast_rooms(new_state)
      broadcast_room(updated_room)
      {:reply, {:ok, updated_room}, new_state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  defp fetch_room(nil), do: {:error, "Room not found"}
  defp fetch_room(room), do: {:ok, room}

  defp fetch_game(%{game: nil}), do: {:error, "Game has not started"}
  defp fetch_game(%{game: game}), do: {:ok, game}

  defp validate_name(name) do
    trimmed = String.trim(name || "")

    cond do
      trimmed == "" -> {:error, "Player name is required"}
      String.length(trimmed) > 20 -> {:error, "Player name must be 20 characters or less"}
      true -> {:ok, trimmed}
    end
  end

  defp validate_session_id(session_id) do
    trimmed = String.trim(session_id || "")

    if trimmed == "",
      do: {:error, "Player session is required"},
      else: {:ok, trimmed}
  end

  defp validate_room_name(name) do
    trimmed = String.trim(name || "")

    cond do
      trimmed == "" -> {:error, "Room name is required"}
      String.length(trimmed) > 40 -> {:error, "Room name must be 40 characters or less"}
      true -> {:ok, trimmed}
    end
  end

  defp validate_max_players(value) when is_integer(value) and value in 2..5, do: {:ok, value}

  defp validate_max_players(value) do
    case Integer.parse(to_string(value || "")) do
      {num, ""} when num in 2..5 -> {:ok, num}
      _ -> {:error, "Max players must be between 2 and 5"}
    end
  end

  defp validate_mode(mode) do
    case mode do
      "Basic" -> {:ok, "Basic"}
      "Advanced" -> {:ok, "Advanced"}
      _ -> {:error, "Mode must be Basic or Advanced"}
    end
  end

  defp ensure_joinable(room, player_session_id) do
    cond do
      player_in_room?(room, player_session_id) -> :ok
      room.status == :waiting -> :ok
      true -> {:error, "Game already started"}
    end
  end

  defp ensure_capacity(room, player_session_id) do
    cond do
      player_in_room?(room, player_session_id) -> :ok
      length(room.players) >= room.max_players -> {:error, "Room is full"}
      true -> :ok
    end
  end

  defp ensure_host(room, player_session_id) do
    if room.host_id == player_session_id,
      do: :ok,
      else: {:error, "Only the host can start the game"}
  end

  defp ensure_minimum_players(room) do
    if length(room.players) >= 2,
      do: :ok,
      else: {:error, "At least 2 players are required to start"}
  end

  defp ensure_setup_phase(%{phase: :character_selection}), do: :ok
  defp ensure_setup_phase(_game), do: {:error, "Character selection is complete"}

  defp ensure_character_setup_phase(%{phase: :character_setup}), do: :ok

  defp ensure_character_setup_phase(_game),
    do: {:error, "Character setup is not active"}

  defp ensure_playing_phase(%{phase: :playing}), do: :ok
  defp ensure_playing_phase(_game), do: {:error, "Trick play is not active"}

  defp ensure_round_complete_phase(%{phase: :round_complete}), do: :ok
  defp ensure_round_complete_phase(_game), do: {:error, "Round is not complete"}

  defp ensure_choose_first_lead_phase(%{phase: :choosing_first_lead}), do: :ok
  defp ensure_choose_first_lead_phase(_game), do: {:error, "First lead choice is not active"}

  defp ensure_no_winner(%{winner_id: winner_id}) when is_binary(winner_id),
    do: {:error, "Game is complete"}

  defp ensure_no_winner(_game), do: :ok

  defp ensure_round_remaining(room, game) do
    if game.round < max_rounds(room),
      do: :ok,
      else: {:error, "No rounds remain"}
  end

  defp ensure_player_in_room(room, player_session_id) do
    if player_in_room?(room, player_session_id),
      do: :ok,
      else: {:error, "Player is not seated at this table"}
  end

  defp ensure_lead_token_holder(game, player_session_id) do
    if game.lead_player_token_id == player_session_id,
      do: :ok,
      else: {:error, "Only the lead player token holder can choose the first lead"}
  end

  defp ensure_player_in_round(game, player_session_id) do
    if player_session_id in (game.character_order || []),
      do: :ok,
      else: {:error, "Choose a seated player"}
  end

  defp ensure_current_picker(game, player_name) do
    if current_picker(game) == player_name,
      do: :ok,
      else: {:error, "It is not your turn to choose"}
  end

  defp ensure_current_setup_player(game, player_name) do
    if current_setup_player(game) == player_name,
      do: :ok,
      else: {:error, "It is not your turn to finish setup"}
  end

  defp ensure_current_player(game, player_session_id) do
    if game.current_player == player_session_id,
      do: :ok,
      else: {:error, "It is not your turn to play"}
  end

  defp ensure_character_available(game, character_id) do
    if character_id in Map.values(game.character_picks),
      do: {:error, "Character has already been chosen"},
      else: :ok
  end

  defp validate_character_id(mode, character_id) do
    normalized = String.trim(character_id || "")

    if normalized in character_ids_for_mode(mode),
      do: {:ok, normalized},
      else: {:error, "Character is not available in this mode"}
  end

  defp character_ids_for_mode("Advanced") do
    ["king", "gambler", "resistance", "hermit", "berserker", "adventurer", "collector", "ruler"]
  end

  defp character_ids_for_mode(_mode) do
    ["king", "gambler", "resistance", "hermit", "berserker"]
  end

  defp current_picker(game), do: Enum.at(game.character_order, game.current_picker_index)

  defp current_setup_player(game),
    do: Enum.at(game.character_setup_order, game.current_setup_index)

  defp ensure_current_character(game, player_session_id, character_id) do
    if Map.get(game.character_picks || %{}, player_session_id) == character_id,
      do: :ok,
      else: {:error, "This setup action is not available for your character"}
  end

  defp apply_character_setup(game, player_session_id, setup_attrs) do
    case Map.get(game.character_picks || %{}, player_session_id) do
      "king" -> apply_king_setup(game, player_session_id, setup_attrs)
      "gambler" -> apply_gambler_setup(game, setup_attrs)
      _character_id -> {:ok, game}
    end
  end

  defp apply_setup_start_bonuses(game) do
    Enum.reduce(game.character_picks, game, fn {player_session_id, character_id}, game ->
      if character_id == "gambler" do
        update_in(game, [:points, player_session_id], &((&1 || 0) + 20))
      else
        game
      end
    end)
  end

  defp apply_king_setup(game, player_session_id, setup_attrs) do
    discard_id = String.trim(setup_attrs["discard"] || "")
    hand = get_in(game, [:hands, player_session_id]) || []

    cond do
      discard_id == "" ->
        {:error, "Choose one card to discard"}

      discard_id == king_rare_card().id ->
        {:error, "King must discard a card from the original hand"}

      not Enum.any?(hand, &(&1.id == discard_id)) ->
        {:error, "Choose a card from your current hand"}

      true ->
        {discarded_cards, kept_cards} = Enum.split_with(hand, &(&1.id == discard_id))

        game =
          game
          |> put_in([:hands, player_session_id], kept_cards ++ [king_rare_card()])
          |> Map.put(:discards, Map.get(game, :discards, []) ++ discarded_cards)

        {:ok, game}
    end
  end

  defp king_rare_card do
    %{id: "king-rare", kind: :rare}
  end

  defp apply_gambler_setup(game, setup_attrs) do
    with {:ok, _bid} <- validate_gambler_bid(setup_attrs["bid"]),
         {:ok, _wager} <- validate_gambler_wager(setup_attrs["wager"], game.round) do
      {:ok, game}
    end
  end

  defp validate_gambler_bid(value) do
    case Integer.parse(to_string(value || "")) do
      {bid, ""} when bid in 0..5 -> {:ok, bid}
      _ -> {:error, "Gambler bid must be between 0 and 5"}
    end
  end

  defp validate_gambler_wager(value, round) do
    max_wager = if round == 3, do: 100, else: 50

    case Integer.parse(to_string(value || "")) do
      {wager, ""} when wager >= 0 and wager <= max_wager -> {:ok, wager}
      _ -> {:error, "Gambler wager must be between 0 and #{max_wager}"}
    end
  end

  defp ensure_gambler_redraw_available(game, player_session_id) do
    redraw_count = game |> Map.get(:gambler_redraws, %{}) |> Map.get(player_session_id, 0)

    if redraw_count < 2,
      do: :ok,
      else: {:error, "Gambler can redraw at most twice"}
  end

  defp validate_redraw_card_ids(game, player_session_id, card_ids) when is_list(card_ids) do
    hand = get_in(game, [:hands, player_session_id]) || []
    hand_ids = MapSet.new(Enum.map(hand, & &1.id))
    discard_ids = Enum.uniq(card_ids)

    cond do
      discard_ids == [] ->
        {:error, "Choose at least one card to redraw"}

      Enum.all?(discard_ids, &MapSet.member?(hand_ids, &1)) ->
        {:ok, discard_ids}

      true ->
        {:error, "Choose cards from your current hand"}
    end
  end

  defp validate_redraw_card_ids(_game, _player_session_id, _card_ids),
    do: {:error, "Choose cards from your current hand"}

  defp redraw_hand(game, player_session_id, discard_ids) do
    draw_pile = Map.get(game, :draw_pile, [])
    draw_count = length(discard_ids)

    if length(draw_pile) < draw_count do
      {:error, "There are not enough cards to redraw"}
    else
      {drawn_cards, remaining_draw_pile} = Enum.split(draw_pile, draw_count)
      hand = get_in(game, [:hands, player_session_id]) || []
      discard_id_set = MapSet.new(discard_ids)

      {new_hand, discarded_cards, _drawn_cards} =
        replace_discarded_cards(hand, discard_id_set, drawn_cards)

      redraws = Map.get(game, :gambler_redraws, %{})
      redraw_count = Map.get(redraws, player_session_id, 0)

      game =
        game
        |> put_in([:hands, player_session_id], new_hand)
        |> Map.put(:draw_pile, remaining_draw_pile)
        |> Map.put(:discards, Map.get(game, :discards, []) ++ discarded_cards)
        |> Map.put(:gambler_redraws, Map.put(redraws, player_session_id, redraw_count + 1))

      {:ok, game}
    end
  end

  defp replace_discarded_cards(hand, discard_id_set, drawn_cards) do
    Enum.reduce(hand, {[], [], drawn_cards}, fn card, {new_hand, discarded_cards, drawn_cards} ->
      if MapSet.member?(discard_id_set, card.id) do
        [replacement | drawn_cards] = drawn_cards
        {new_hand ++ [replacement], discarded_cards ++ [card], drawn_cards}
      else
        {new_hand ++ [card], discarded_cards, drawn_cards}
      end
    end)
  end

  defp start_playing_if_ready(game, false), do: Map.put(game, :phase, :character_setup)

  defp start_playing_if_ready(game, true) do
    if game.round > 1 and is_binary(Map.get(game, :lead_player_token_id)) do
      Map.put(game, :phase, :choosing_first_lead)
    else
      lead = game.lead || hd(game.character_order)

      game
      |> Map.put(:phase, :playing)
      |> Map.put(:current_player, lead)
      |> Map.put(:current_trick, [])
    end
  end

  defp start_next_round(room, game) do
    player_ids = Enum.map(room.players, & &1.id)
    lead_player_token_id = game.next_lead_player_id || game.lead_player_token_id || hd(player_ids)
    {hands, draw_pile} = Deck.deal_with_draw_pile(player_ids)

    game =
      game
      |> Map.put(:phase, :character_selection)
      |> Map.update!(:round, &(&1 + 1))
      |> Map.put(:trick, 1)
      |> Map.put(:lead, nil)
      |> Map.put(:current_player, nil)
      |> Map.put(:current_trick, [])
      |> Map.put(:completed_tricks, [])
      |> Map.put(:trick_wins, %{})
      |> Map.put(:lead_player_token_id, lead_player_token_id)
      |> Map.put(:character_order, rotate_player_order(player_ids, lead_player_token_id))
      |> Map.put(:hands, hands)
      |> Map.put(:draw_pile, draw_pile)
      |> Map.put(:discards, [])
      |> Map.put(:gambler_redraws, %{})
      |> Map.put(:character_picks, %{})
      |> Map.put(:current_picker_index, 0)
      |> Map.put(:character_setup_order, [])
      |> Map.put(:character_setup_done, %{})
      |> Map.put(:current_setup_index, 0)
      |> Map.put(:round_result, nil)
      |> Map.put(:next_lead_player_id, nil)
      |> Map.put(:winner_id, nil)
      |> Map.put(:win_reason, nil)

    {:ok, game}
  end

  defp fetch_hand_card(game, player_session_id, card_id) do
    game
    |> get_in([:hands, player_session_id])
    |> Kernel.||([])
    |> Enum.find(&(&1.id == card_id))
    |> case do
      nil -> {:error, "Choose a card from your hand"}
      card -> {:ok, card}
    end
  end

  defp ensure_legal_play(game, player_session_id, card) do
    hand = get_in(game, [:hands, player_session_id]) || []

    if Trick.legal_card?(hand, card, game.current_trick || []),
      do: :ok,
      else: {:error, "You must follow the lead suit if able"}
  end

  defp play_card_in_game(game, player_session_id, card) do
    hand = get_in(game, [:hands, player_session_id]) || []
    hand = Enum.reject(hand, &(&1.id == card.id))
    current_trick = (game.current_trick || []) ++ [%{player_id: player_session_id, card: card}]

    game =
      game
      |> put_in([:hands, player_session_id], hand)
      |> Map.put(:current_trick, current_trick)

    {:ok, advance_trick_if_complete(game)}
  end

  defp advance_trick_if_complete(game) do
    if length(game.current_trick) == length(game.character_order) do
      winner_id = Trick.winning_play(game.current_trick).player_id

      completed_trick = %{
        trick: game.trick,
        lead_suit: Trick.lead_suit(game.current_trick),
        plays: game.current_trick,
        winner_id: winner_id
      }

      game =
        game
        |> Map.put(:completed_tricks, Map.get(game, :completed_tricks, []) ++ [completed_trick])
        |> Map.put(
          :trick_wins,
          Map.update(Map.get(game, :trick_wins, %{}), winner_id, 1, &(&1 + 1))
        )
        |> Map.put(
          :discards,
          Map.get(game, :discards, []) ++ Enum.map(game.current_trick, & &1.card)
        )
        |> Map.put(:current_trick, [])
        |> Map.put(:lead, winner_id)
        |> Map.put(:current_player, winner_id)

      if length(game.completed_tricks) == 5 do
        complete_round(game)
      else
        Map.update!(game, :trick, &(&1 + 1))
      end
    else
      Map.put(game, :current_player, next_player_after(game.character_order, game.current_player))
    end
  end

  defp complete_round(game) do
    result = Round.resolve(game)
    winner_id = result.character_winner_id || result.crown_winner_id
    lead_player_token_id = result.next_lead_player_id || Map.get(game, :lead_player_token_id)

    game
    |> Map.put(:phase, :round_complete)
    |> Map.put(:round_result, result)
    |> Map.put(:crowns, result.crowns)
    |> Map.put(:points, result.points_after)
    |> Map.put(:next_lead_player_id, result.next_lead_player_id)
    |> Map.put(:lead_player_token_id, lead_player_token_id)
    |> Map.put(:winner_id, winner_id)
    |> Map.put(:win_reason, win_reason(result))
  end

  defp max_rounds(%{max_players: 2}), do: 5
  defp max_rounds(_room), do: 3

  defp rotate_player_order(player_ids, player_id) do
    index = Enum.find_index(player_ids, &(&1 == player_id)) || 0
    {before, after_and_player} = Enum.split(player_ids, index)
    after_and_player ++ before
  end

  defp win_reason(%{character_winner_id: winner_id}) when is_binary(winner_id), do: :character
  defp win_reason(%{crown_winner_id: winner_id}) when is_binary(winner_id), do: :crown
  defp win_reason(_result), do: nil

  defp next_player_after(player_ids, player_id) do
    index = Enum.find_index(player_ids, &(&1 == player_id)) || 0
    Enum.at(player_ids, rem(index + 1, length(player_ids)))
  end

  defp next_picker_index(game, picks) do
    Enum.find_index(game.character_order, fn player -> not Map.has_key?(picks, player) end) ||
      game.current_picker_index
  end

  defp next_setup_index(game, setup_done) do
    Enum.find_index(game.character_setup_order, fn player ->
      not Map.has_key?(setup_done, player)
    end) || game.current_setup_index
  end

  defp character_setup_order(character_order, picks) do
    Enum.sort_by(character_order, fn player ->
      picks
      |> Map.get(player)
      |> character_priority_rank()
    end)
  end

  defp character_priority_rank("king"), do: 1
  defp character_priority_rank("gambler"), do: 2
  defp character_priority_rank("resistance"), do: 3
  defp character_priority_rank("adventurer"), do: 4
  defp character_priority_rank("hermit"), do: 5
  defp character_priority_rank("collector"), do: 6
  defp character_priority_rank("berserker"), do: 7
  defp character_priority_rank("ruler"), do: 8
  defp character_priority_rank(_character_id), do: 99

  defp normalize_setup_attrs(attrs) when is_map(attrs) do
    Map.take(attrs, ["discard", "bid", "wager", "notes"])
  end

  defp normalize_setup_attrs(_attrs), do: %{}

  defp player_for_session(nil, _player_session_id), do: nil

  defp player_for_session(room, player_session_id) do
    Enum.find(room.players, &(&1.id == player_session_id))
  end

  defp unique_code(rooms) do
    code =
      for _ <- 1..4, into: "" do
        <<Enum.random(?A..?Z)>>
      end

    if Map.has_key?(rooms, code), do: unique_code(rooms), else: code
  end

  defp broadcast_rooms(state) do
    Phoenix.PubSub.broadcast(
      TricktakersWeb.PubSub,
      @topic,
      {:rooms_updated, Map.values(state.rooms)}
    )
  end

  defp broadcast_room(room) do
    Phoenix.PubSub.broadcast(TricktakersWeb.PubSub, room_topic(room.code), {:room_updated, room})
  end

  defp broadcast_game_started(room) do
    Phoenix.PubSub.broadcast(TricktakersWeb.PubSub, room_topic(room.code), {:game_started, room})
  end

  defp room_topic(code), do: "room:" <> String.upcase(code)
end
