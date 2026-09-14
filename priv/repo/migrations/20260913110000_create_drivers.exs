defmodule CoreApp.Repo.Migrations.CreateDrivers do
  use Ecto.Migration

  def change do
    create table(:drivers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :office_id, references(:offices, type: :binary_id, on_delete: :restrict), null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      add :code, :string, size: 20, null: false
      add :name, :string, size: 100, null: false
      add :name_kana, :string, size: 100, null: false
      add :employment_type, :string, null: false
      add :hired_on, :date, null: false
      add :retired_on, :date

      add :license_number, :string, size: 20, null: false
      add :license_types, {:array, :string}, null: false
      add :license_expires_on, :date, null: false

      add :note, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index(:drivers, [:code])
    create index(:drivers, [:office_id])
    create index(:drivers, [:employment_type])
    create index(:drivers, [:office_id, :employment_type])
    create index(:drivers, [:license_expires_on])

    # 1運転者につきアカウントは1つまで（V-7）。未紐付け（NULL）は重複を許す。
    create unique_index(:drivers, [:user_id], where: "user_id IS NOT NULL")
  end
end
