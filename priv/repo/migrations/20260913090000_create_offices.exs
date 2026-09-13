defmodule CoreApp.Repo.Migrations.CreateOffices do
  use Ecto.Migration

  def change do
    create table(:offices, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :code, :string, size: 20, null: false
      add :name, :string, size: 100, null: false
      add :postal_code, :string, size: 8
      add :address, :string, size: 255
      add :phone, :string, size: 20
      add :active, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create unique_index(:offices, [:code])
  end
end
