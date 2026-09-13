defmodule CoreApp.Repo.Migrations.CreateVehicles do
  use Ecto.Migration

  def change do
    create table(:vehicles, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :office_id, references(:offices, type: :binary_id, on_delete: :restrict), null: false

      add :plate_number, :string, size: 30, null: false
      add :vin, :string, size: 30, null: false
      add :vehicle_class, :string, null: false
      add :maker, :string, size: 50, null: false
      add :model_name, :string, size: 100, null: false
      add :first_registered_on, :date, null: false
      add :status, :string, null: false, default: "active"

      add :capacity_kg, :integer
      add :gross_weight_kg, :integer
      add :seating_capacity, :integer
      add :fuel_type, :string
      add :ownership, :string
      add :lease_expires_on, :date

      add :inspection_expires_on, :date, null: false
      add :liability_insurance_expires_on, :date, null: false
      add :voluntary_insurance_expires_on, :date
      add :next_periodic_3m_on, :date
      add :next_periodic_12m_on, :date

      add :latest_odometer, :integer
      add :note, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index(:vehicles, [:plate_number])
    create index(:vehicles, [:office_id])
    create index(:vehicles, [:status])
    create index(:vehicles, [:office_id, :status])
    create index(:vehicles, [:inspection_expires_on])
    create index(:vehicles, [:liability_insurance_expires_on])
    create index(:vehicles, [:voluntary_insurance_expires_on])
    create index(:vehicles, [:next_periodic_3m_on])
    create index(:vehicles, [:next_periodic_12m_on])
  end
end
