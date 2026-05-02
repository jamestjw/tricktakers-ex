defmodule TricktakersWeb.RoomRegistry do
  use GenServer

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

      game = %{
        started_at: DateTime.utc_now(),
        phase: :character_selection,
        round: 1,
        trick: 1,
        lead: hd(player_ids),
        character_order: player_ids,
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
         :ok <- ensure_current_setup_player(game, valid_session_id) do
      setup_done =
        Map.put(game.character_setup_done, valid_session_id, normalize_setup_attrs(attrs))

      all_setup? = map_size(setup_done) == length(game.character_setup_order)

      game =
        game
        |> Map.put(:character_setup_done, setup_done)
        |> Map.put(:current_setup_index, next_setup_index(game, setup_done))
        |> Map.put(:phase, if(all_setup?, do: :playing, else: :character_setup))

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

  defp room_topic(code), do: "room:" <> String.upcase(code)
end
