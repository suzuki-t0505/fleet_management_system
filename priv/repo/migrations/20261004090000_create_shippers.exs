defmodule CoreApp.Repo.Migrations.CreateShippers do
  use Ecto.Migration

  def change do
    create table(:shippers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :office_id, references(:offices, type: :binary_id, on_delete: :restrict), null: false

      add :name, :string, size: 255, null: false
      add :code, :string, size: 50
      add :note, :text
      add :status, :string, null: false, default: "active"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:shippers, [:office_id, :name])
    create index(:shippers, [:office_id, :status])
  end
end
