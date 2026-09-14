defmodule CoreApp.Repo.Migrations.CreateOperationReports do
  use Ecto.Migration

  def change do
    create table(:operation_reports, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :office_id, references(:offices, type: :binary_id, on_delete: :restrict), null: false
      add :vehicle_id, references(:vehicles, type: :binary_id, on_delete: :restrict), null: false
      add :driver_id, references(:drivers, type: :binary_id, on_delete: :restrict), null: false

      add :created_by_user_id, references(:users, type: :binary_id, on_delete: :restrict),
        null: false

      add :operation_date, :date, null: false
      add :departed_at, :utc_datetime, null: false
      add :returned_at, :utc_datetime, null: false
      add :start_odometer, :integer, null: false
      add :end_odometer, :integer, null: false
      add :distance_km, :integer, null: false

      add :destination, :string, size: 255
      add :cargo_type, :string, size: 100
      add :rest_minutes, :integer

      add :status, :string, null: false, default: "draft"
      add :submitted_at, :utc_datetime
      add :approved_by_user_id, references(:users, type: :binary_id, on_delete: :restrict)
      add :approved_at, :utc_datetime
      add :rejected_reason, :text
      add :note, :text

      timestamps(type: :utc_datetime)
    end

    create index(:operation_reports, [:office_id, :operation_date])
    create index(:operation_reports, [:vehicle_id, :operation_date])
    create index(:operation_reports, [:driver_id, :operation_date])
    create index(:operation_reports, [:status, :office_id])

    create table(:refuelings, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :operation_report_id,
          references(:operation_reports, type: :binary_id, on_delete: :delete_all),
          null: false

      add :refueled_at, :utc_datetime, null: false
      add :liters, :decimal, precision: 6, scale: 2, null: false
      add :amount_yen, :integer
      add :odometer, :integer

      timestamps(type: :utc_datetime)
    end

    create index(:refuelings, [:operation_report_id])
  end
end
