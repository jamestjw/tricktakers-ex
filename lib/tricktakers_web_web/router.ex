defmodule TricktakersWebWeb.Router do
  use TricktakersWebWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {TricktakersWebWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", TricktakersWebWeb do
    pipe_through :browser

    live "/", LobbyLive, :landing
    live "/lobby", LobbyLive, :index
    live "/characters", CharactersLive, :index
    live "/rooms/:code", RoomLive, :show
    live "/games/:code", GameLive, :show
  end

  # Other scopes may use custom stacks.
  # scope "/api", TricktakersWebWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard in development
  if Application.compile_env(:tricktakers_web, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: TricktakersWebWeb.Telemetry
    end
  end
end
