defmodule CoreApp.Repo.Migrations.CreateDispatchDeliveries do
  use Ecto.Migration

  def change do
    create table(:dispatch_deliveries, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :dispatch_id, references(:dispatches, type: :binary_id, on_delete: :delete_all),
        null: false

      add :position, :integer, null: false, default: 0
      add :destination, :string, size: 255, null: false
      add :fare_yen, :integer

      timestamps(type: :utc_datetime)
    end

    create index(:dispatch_deliveries, [:dispatch_id, :position])
  end
end
