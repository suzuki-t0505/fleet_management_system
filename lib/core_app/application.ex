defmodule CoreApp.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      CoreAppWeb.Telemetry,
      CoreApp.Repo,
      {DNSCluster, query: Application.get_env(:core_app, :dns_cluster_query) || :ignore},
      {Oban, Application.fetch_env!(:core_app, Oban)},
      {Phoenix.PubSub, name: CoreApp.PubSub},
      # Start a worker by calling: CoreApp.Worker.start_link(arg)
      # {CoreApp.Worker, arg},
      # Start to serve requests, typically the last entry
      CoreAppWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: CoreApp.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    CoreAppWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
