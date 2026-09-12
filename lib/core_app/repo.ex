defmodule CoreApp.Repo do
  use Ecto.Repo,
    otp_app: :core_app,
    adapter: Ecto.Adapters.Postgres
end
