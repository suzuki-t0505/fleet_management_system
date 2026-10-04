defmodule CoreApp.Repo.Migrations.CreateDispatches do
  use Ecto.Migration

  def change do
    create table(:dispatches, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :office_id, references(:offices, type: :binary_id, on_delete: :restrict), null: false
      add :shipper_id, references(:shippers, type: :binary_id, on_delete: :restrict), null: false
      add :vehicle_id, references(:vehicles, type: :binary_id, on_delete: :restrict), null: false
      add :driver_id, references(:drivers, type: :binary_id, on_delete: :restrict), null: false

      add :created_by_user_id, references(:users, type: :binary_id, on_delete: :restrict),
        null: false

      add :title, :string, size: 255, null: false
      add :description, :text
      add :started_at, :utc_datetime, null: false
      add :ended_at, :utc_datetime, null: false

      add :pricing_type, :string, null: false
      add :course_fare_yen, :integer
      add :toll_yen, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:dispatches, [:office_id, :started_at])
    create index(:dispatches, [:vehicle_id, :started_at])
    create index(:dispatches, [:driver_id, :started_at])
    create index(:dispatches, [:shipper_id])
  end
end
