defmodule TricktakersWebWeb.Plugs.EnsurePlayerSession do
  @moduledoc false

  import Plug.Conn

  @session_key :player_session_id

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_session(conn, @session_key) do
      nil -> put_session(conn, @session_key, new_session_id())
      _session_id -> conn
    end
  end

  defp new_session_id do
    32
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end
end
