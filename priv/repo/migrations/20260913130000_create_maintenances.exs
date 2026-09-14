defmodule CoreApp.Repo.Migrations.CreateMaintenances do
  use Ecto.Migration

  def change do
    create table(:maintenances, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :vehicle_id, references(:vehicles, type: :binary_id, on_delete: :restrict), null: false
      add :office_id, references(:offices, type: :binary_id, on_delete: :restrict), null: false

      add :created_by_user_id, references(:users, type: :binary_id, on_delete: :restrict),
        null: false

      add :performed_on, :date, null: false
      add :category, :string, null: false
      add :odometer, :integer, null: false
      add :vendor, :string, size: 100, null: false
      add :cost_yen, :integer
      add :description, :text
      add :next_scheduled_on, :date

      timestamps(type: :utc_datetime)
    end

    create index(:maintenances, [:vehicle_id, :performed_on])
    create index(:maintenances, [:office_id, :performed_on])
    create index(:maintenances, [:category])
  end
end
