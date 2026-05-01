defmodule TricktakersWeb.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      TricktakersWebWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:tricktakers_web, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: TricktakersWeb.PubSub},
      # Start a worker by calling: TricktakersWeb.Worker.start_link(arg)
      # {TricktakersWeb.Worker, arg},
      # Start to serve requests, typically the last entry
      TricktakersWebWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: TricktakersWeb.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    TricktakersWebWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
