defmodule CoreApp.Repo.Migrations.CreateIncidents do
  use Ecto.Migration

  def change do
    create table(:incidents, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :office_id, references(:offices, type: :binary_id, on_delete: :restrict), null: false
      add :vehicle_id, references(:vehicles, type: :binary_id, on_delete: :restrict), null: false
      add :driver_id, references(:drivers, type: :binary_id, on_delete: :restrict)

      add :reported_by_user_id, references(:users, type: :binary_id, on_delete: :restrict),
        null: false

      add :occurred_at, :utc_datetime, null: false
      add :category, :string, null: false
      add :place, :string, size: 255, null: false
      add :weather, :string, null: false
      add :description, :text, null: false
      add :counterpart, :text
      add :damage, :text
      add :police_reported, :boolean, null: false, default: false

      add :status, :string, null: false, default: "reported"
      add :shared_company_wide, :boolean, null: false, default: false

      add :direct_cause, :text
      add :background_factor, :text
      add :countermeasure, :text
      add :countermeasure_due_on, :date
      add :countermeasure_owner, :string, size: 100

      add :approved_by_user_id, references(:users, type: :binary_id, on_delete: :restrict)
      add :approved_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:incidents, [:office_id, :occurred_at])
    create index(:incidents, [:vehicle_id, :occurred_at])
    create index(:incidents, [:driver_id])
    create index(:incidents, [:status, :office_id])
    create index(:incidents, [:category])
    create index(:incidents, [:shared_company_wide])
  end
end
