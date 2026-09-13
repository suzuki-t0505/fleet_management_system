defmodule CoreApp.Maintenances.Maintenance do
  @moduledoc false
  use CoreApp.Schema
  import Ecto.Changeset

  alias CoreApp.Accounts.User
  alias CoreApp.Offices.Office
  alias CoreApp.Utils.ConvertDatetime
  alias CoreApp.Vehicles.Vehicle

  @categories ~w(inspection periodic_3m periodic_12m daily repair oil tire other)a
  @deadline_categories ~w(inspection periodic_3m periodic_12m)a

  # 区分と、実施時に更新する車両側の期限カラムの対応（V-20・V-21）
  @deadline_fields %{
    inspection: :inspection_expires_on,
    periodic_3m: :next_periodic_3m_on,
    periodic_12m: :next_periodic_12m_on
  }

  schema "maintenances" do
    field :performed_on, :date
    field :category, Ecto.Enum, values: @categories
    field :odometer, :integer
    field :vendor, :string
    field :cost_yen, :integer
    field :description, :string
    field :next_scheduled_on, :date

    belongs_to(:vehicle, Vehicle)
    belongs_to(:office, Office)
    belongs_to(:created_by_user, User)

    timestamps(type: :utc_datetime)
  end

  @doc """
  点検整備の区分の一覧を返します。
  """
  def categories, do: @categories

  @doc """
  次回予定日の入力が必須になる区分の一覧を返します（V-20・V-21）。
  """
  def deadline_categories, do: @deadline_categories

  @doc """
  区分に対応する車両側の期限カラムを返します。対応が無い区分は `nil` を返します。

  ```elixir
  iex> deadline_field(:inspection)
  :inspection_expires_on
  ```
  """
  def deadline_field(category), do: Map.get(@deadline_fields, category)

  @doc """
  点検整備記録のchangesetです。
  """
  def changeset(maintenance, attrs) do
    maintenance
    |> cast(attrs, [
      :vehicle_id,
      :office_id,
      :created_by_user_id,
      :performed_on,
      :category,
      :odometer,
      :vendor,
      :cost_yen,
      :description,
      :next_scheduled_on
    ])
    |> validate_required([
      :vehicle_id,
      :office_id,
      :created_by_user_id,
      :performed_on,
      :category,
      :odometer,
      :vendor
    ])
    |> validate_length(:vendor, max: 100)
    |> validate_number(:odometer, greater_than_or_equal_to: 0)
    |> validate_number(:cost_yen, greater_than_or_equal_to: 0)
    |> validate_performed_on()
    |> validate_next_scheduled_on()
    |> assoc_constraint(:vehicle)
    |> assoc_constraint(:office)
  end

  # V-22: 実施日に未来日は入力できない
  defp validate_performed_on(changeset) do
    validate_change(changeset, :performed_on, fn :performed_on, value ->
      if Date.after?(value, ConvertDatetime.today()) do
        [performed_on: "に未来の日付は入力できません"]
      else
        []
      end
    end)
  end

  # V-20・V-21: 車検・法定点検は次回予定日が必須。加えて実施日以降でなければならない。
  defp validate_next_scheduled_on(changeset) do
    changeset
    |> validate_next_scheduled_on_required(get_field(changeset, :category))
    |> validate_next_scheduled_on_order(get_field(changeset, :performed_on))
  end

  defp validate_next_scheduled_on_required(changeset, :inspection) do
    validate_required(changeset, [:next_scheduled_on], message: "（新しい車検満了日）を入力してください")
  end

  defp validate_next_scheduled_on_required(changeset, category)
       when category in [:periodic_3m, :periodic_12m] do
    validate_required(changeset, [:next_scheduled_on], message: "（次回の点検予定日）を入力してください")
  end

  defp validate_next_scheduled_on_required(changeset, _category), do: changeset

  defp validate_next_scheduled_on_order(changeset, nil), do: changeset

  defp validate_next_scheduled_on_order(changeset, performed_on) do
    validate_change(changeset, :next_scheduled_on, fn :next_scheduled_on, value ->
      if Date.before?(value, performed_on) do
        [next_scheduled_on: "は実施日以降の日付を入力してください"]
      else
        []
      end
    end)
  end
end
