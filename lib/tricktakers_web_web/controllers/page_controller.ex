defmodule TricktakersWebWeb.PageController do
  use TricktakersWebWeb, :controller

  def home(conn, _params) do
    redirect(conn, external: "/tricktakers/index.html")
  end

  def characters(conn, _params) do
    redirect(conn, external: "/tricktakers/characters.html")
  end

  def screen(conn, %{"name" => name}) do
    file =
      case name do
        "overview" -> "index.html"
        "landing" -> "landing.html"
        "lobby" -> "lobby.html"
        "setup" -> "setup.html"
        "table" -> "table.html"
        "trick" -> "resolve.html"
        "round" -> "round.html"
        "characters" -> "characters.html"
        "profile" -> "profile.html"
        _ -> "index.html"
      end

    redirect(conn, external: "/tricktakers/#{file}")
  end
end
