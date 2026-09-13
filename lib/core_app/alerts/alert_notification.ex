defmodule CoreApp.Alerts.AlertNotification do
  @moduledoc false
  use CoreApp.Schema
  import Ecto.Changeset

  @target_types ~w(vehicle driver)a
  @alert_types ~w(inspection liability_insurance voluntary_insurance periodic_3m periodic_12m license)a
  @notify_stages ~w(d60 d30 d7 d0 overdue)a
  @statuses ~w(sent failed)a

  # 期限前に通知する残日数と、その段階の対応
  @stages_by_days %{60 => :d60, 30 => :d30, 7 => :d7, 0 => :d0}

  # 超過中の再通知の間隔（日）
  @overdue_interval_days 7

  schema "alert_notifications" do
    field :target_type, Ecto.Enum, values: @target_types
    field :target_id, Ecto.ULID
    field :alert_type, Ecto.Enum, values: @alert_types
    field :deadline_on, :date
    field :notify_stage, Ecto.Enum, values: @notify_stages
    field :notified_on, :date
    field :sent_at, :utc_datetime
    field :status, Ecto.Enum, values: @statuses
    field :error_message, :string

    timestamps(type: :utc_datetime)
  end

  @doc """
  通知の段階の一覧を返します。
  """
  def notify_stages, do: @notify_stages

  @doc """
  超過中の再通知の間隔（日）を返します。
  """
  def overdue_interval_days, do: @overdue_interval_days

  @doc """
  残日数から通知すべき段階を返します。通知しない日は `nil` を返します。

  期限前は残り 60 / 30 / 7 / 0 日のちょうどその日だけ、超過後は
  #{@overdue_interval_days} 日ごとに通知します（超過中の毎日は通知しません）。

  ```elixir
  iex> stage_for(30)
  :d30
  iex> stage_for(-14)
  :overdue
  iex> stage_for(-13)
  nil
  ```
  """
  def stage_for(days_left) when is_integer(days_left) and days_left >= 0 do
    Map.get(@stages_by_days, days_left)
  end

  def stage_for(days_left) when is_integer(days_left) do
    if rem(abs(days_left), @overdue_interval_days) == 0, do: :overdue
  end

  @doc """
  通知ログのchangesetです。
  """
  def changeset(notification, attrs) do
    notification
    |> cast(attrs, [
      :target_type,
      :target_id,
      :alert_type,
      :deadline_on,
      :notify_stage,
      :notified_on,
      :sent_at,
      :status,
      :error_message
    ])
    |> validate_required([
      :target_type,
      :target_id,
      :alert_type,
      :deadline_on,
      :notify_stage,
      :notified_on,
      :status
    ])
    |> unique_constraint(
      [:target_type, :target_id, :alert_type, :deadline_on, :notify_stage, :notified_on],
      name: :alert_notifications_stage_index
    )
  end
end
