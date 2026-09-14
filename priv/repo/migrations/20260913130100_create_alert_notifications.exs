defmodule CoreApp.Repo.Migrations.CreateAlertNotifications do
  use Ecto.Migration

  def change do
    create table(:alert_notifications, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # 対象は車両と運転者の2種類のため、外部キー制約は張らない
      add :target_type, :string, null: false
      add :target_id, :binary_id, null: false

      add :alert_type, :string, null: false
      add :deadline_on, :date, null: false
      add :notify_stage, :string, null: false
      add :notified_on, :date, null: false
      add :sent_at, :utc_datetime
      add :status, :string, null: false
      add :error_message, :text

      timestamps(type: :utc_datetime)
    end

    create index(:alert_notifications, [:target_type, :target_id])

    # 同一段階の重複送信を防ぐ。超過（overdue）は7日ごとに送るため通知日を含める。
    create unique_index(
             :alert_notifications,
             [:target_type, :target_id, :alert_type, :deadline_on, :notify_stage, :notified_on],
             name: :alert_notifications_stage_index
           )
  end
end
