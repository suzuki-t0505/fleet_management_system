defmodule CoreApp.Repo.Migrations.CreateAttachments do
  use Ecto.Migration

  def change do
    create table(:attachments, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # 対象は車両・点検整備・事故ヒヤリの3種類のため、外部キー制約は張らない
      add :attachable_type, :string, null: false
      add :attachable_id, :binary_id, null: false

      add :filename, :string, size: 255, null: false
      add :content_type, :string, size: 100, null: false
      add :byte_size, :integer, null: false
      add :storage_key, :string, size: 500, null: false

      add :uploaded_by_user_id, references(:users, type: :binary_id, on_delete: :restrict),
        null: false

      timestamps(type: :utc_datetime)
    end

    create index(:attachments, [:attachable_type, :attachable_id])
  end
end
