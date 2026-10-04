defmodule CoreApp.Repo.Migrations.AddLoadingTimesToDispatchDeliveries do
  use Ecto.Migration

  def change do
    alter table(:dispatch_deliveries) do
      add :loading_at, :utc_datetime
      add :unloading_at, :utc_datetime
    end
  end
end
