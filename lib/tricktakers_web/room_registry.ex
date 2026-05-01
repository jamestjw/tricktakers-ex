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

  def create_room(attrs) do
    GenServer.call(__MODULE__, {:create_room, attrs})
  end

  def join_room(code, player_name) do
    GenServer.call(__MODULE__, {:join_room, code, player_name})
  end

  def start_game(code, player_name) do
    GenServer.call(__MODULE__, {:start_game, code, player_name})
  end

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

  def handle_call({:create_room, attrs}, _from, state) do
    with {:ok, player_name} <- validate_name(attrs["player_name"]),
         {:ok, room_name} <- validate_room_name(attrs["room_name"]),
         {:ok, max_players} <- validate_max_players(attrs["max_players"]),
         {:ok, mode} <- validate_mode(attrs["mode"]) do
      code = unique_code(state.rooms)
      now = DateTime.utc_now()

      room = %{
        code: code,
        name: room_name,
        host: player_name,
        max_players: max_players,
        mode: mode,
        status: :waiting,
        players: [player_name],
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

  def handle_call({:join_room, code, player_name}, _from, state) do
    room = Map.get(state.rooms, String.upcase(code || ""))

    with {:ok, found_room} <- fetch_room(room),
         {:ok, valid_name} <- validate_name(player_name),
         :ok <- ensure_waiting(found_room),
         :ok <- ensure_capacity(found_room, valid_name) do
      players =
        if valid_name in found_room.players do
          found_room.players
        else
          found_room.players ++ [valid_name]
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

  def handle_call({:start_game, code, player_name}, _from, state) do
    room = Map.get(state.rooms, String.upcase(code || ""))

    with {:ok, found_room} <- fetch_room(room),
         {:ok, valid_name} <- validate_name(player_name),
         :ok <- ensure_host(found_room, valid_name),
         :ok <- ensure_minimum_players(found_room) do
      game = %{
        started_at: DateTime.utc_now(),
        round: 1,
        trick: 1,
        lead: hd(found_room.players)
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

  defp fetch_room(nil), do: {:error, "Room not found"}
  defp fetch_room(room), do: {:ok, room}

  defp validate_name(name) do
    trimmed = String.trim(name || "")

    cond do
      trimmed == "" -> {:error, "Player name is required"}
      String.length(trimmed) > 20 -> {:error, "Player name must be 20 characters or less"}
      true -> {:ok, trimmed}
    end
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

  defp ensure_waiting(%{status: :waiting}), do: :ok
  defp ensure_waiting(_room), do: {:error, "Game already started"}

  defp ensure_capacity(room, player_name) do
    cond do
      player_name in room.players -> :ok
      length(room.players) >= room.max_players -> {:error, "Room is full"}
      true -> :ok
    end
  end

  defp ensure_host(room, player_name) do
    if room.host == player_name, do: :ok, else: {:error, "Only the host can start the game"}
  end

  defp ensure_minimum_players(room) do
    if length(room.players) >= 2,
      do: :ok,
      else: {:error, "At least 2 players are required to start"}
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
