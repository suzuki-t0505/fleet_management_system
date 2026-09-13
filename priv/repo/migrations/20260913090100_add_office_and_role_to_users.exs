defmodule CoreApp.Repo.Migrations.AddOfficeAndRoleToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :office_id, references(:offices, type: :binary_id, on_delete: :restrict), null: false
      add :name, :string, size: 100, null: false
      add :role, :string, null: false, default: "member"
      add :active, :boolean, null: false, default: true
      add :failed_attempts, :integer, null: false, default: 0
      add :locked_until, :utc_datetime
    end

    create index(:users, [:office_id])
    create index(:users, [:role])
  end
end
