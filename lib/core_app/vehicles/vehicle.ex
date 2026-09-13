defmodule CoreApp.Vehicles.Vehicle do
  @moduledoc false
  use CoreApp.Schema
  import Ecto.Changeset

  alias CoreApp.Offices.Office
  alias CoreApp.Utils.ConvertDatetime

  @vehicle_classes ~w(large medium semi_medium ordinary light other)a
  @statuses ~w(active maintenance idle scrapped)a
  @fuel_types ~w(diesel gasoline hybrid ev other)a
  @ownerships ~w(owned lease)a

  @deadline_fields ~w(
    inspection_expires_on
    liability_insurance_expires_on
    voluntary_insurance_expires_on
    next_periodic_3m_on
    next_periodic_12m_on
    lease_expires_on
  )a

  schema "vehicles" do
    field :plate_number, :string
    field :vin, :string
    field :vehicle_class, Ecto.Enum, values: @vehicle_classes
    field :maker, :string
    field :model_name, :string
    field :first_registered_on, :date
    field :status, Ecto.Enum, values: @statuses, default: :active

    field :capacity_kg, :integer
    field :gross_weight_kg, :integer
    field :seating_capacity, :integer
    field :fuel_type, Ecto.Enum, values: @fuel_types
    field :ownership, Ecto.Enum, values: @ownerships
    field :lease_expires_on, :date

    field :inspection_expires_on, :date
    field :liability_insurance_expires_on, :date
    field :voluntary_insurance_expires_on, :date
    field :next_periodic_3m_on, :date
    field :next_periodic_12m_on, :date

    field :latest_odometer, :integer
    field :note, :string

    belongs_to(:office, Office)

    timestamps(type: :utc_datetime)
  end

  @doc """
  車種区分の一覧を返します。
  """
  def vehicle_classes, do: @vehicle_classes

  @doc """
  車両ステータスの一覧を返します。
  """
  def statuses, do: @statuses

  @doc """
  燃料種別の一覧を返します。
  """
  def fuel_types, do: @fuel_types

  @doc """
  所有区分の一覧を返します。
  """
  def ownerships, do: @ownerships

  @doc """
  期限として監視する項目の一覧を返します。
  """
  def deadline_fields, do: @deadline_fields

  def changeset(vehicle, attrs) do
    vehicle
    |> cast(attrs, [
      :office_id,
      :plate_number,
      :vin,
      :vehicle_class,
      :maker,
      :model_name,
      :first_registered_on,
      :status,
      :capacity_kg,
      :gross_weight_kg,
      :seating_capacity,
      :fuel_type,
      :ownership,
      :lease_expires_on,
      :inspection_expires_on,
      :liability_insurance_expires_on,
      :voluntary_insurance_expires_on,
      :next_periodic_3m_on,
      :next_periodic_12m_on,
      :note
    ])
    |> validate_required([
      :office_id,
      :plate_number,
      :vin,
      :vehicle_class,
      :maker,
      :model_name,
      :first_registered_on,
      :status,
      :inspection_expires_on,
      :liability_insurance_expires_on
    ])
    |> validate_length(:plate_number, max: 30)
    |> validate_length(:vin, max: 30)
    |> validate_length(:maker, max: 50)
    |> validate_length(:model_name, max: 100)
    |> validate_positive_numbers()
    |> validate_first_registered_on()
    |> validate_deadlines()
    |> unique_constraint(:plate_number, message: "この車両番号は既に登録されています")
    |> assoc_constraint(:office)
  end

  # V-2: 各期限日は初度登録年月以降でなければならない
  defp validate_deadlines(changeset) do
    first_registered_on = get_field(changeset, :first_registered_on)

    Enum.reduce(@deadline_fields, changeset, fn field, acc ->
      validate_after_first_registration(acc, field, first_registered_on)
    end)
  end

  defp validate_after_first_registration(changeset, _field, nil), do: changeset

  defp validate_after_first_registration(changeset, field, first_registered_on) do
    validate_change(changeset, field, fn ^field, value ->
      if Date.before?(value, first_registered_on) do
        [{field, "は初度登録年月より後の日付を入力してください"}]
      else
        []
      end
    end)
  end

  defp validate_first_registered_on(changeset) do
    validate_change(changeset, :first_registered_on, fn :first_registered_on, value ->
      if Date.after?(value, ConvertDatetime.today()) do
        [first_registered_on: "に未来の日付は入力できません"]
      else
        []
      end
    end)
  end

  defp validate_positive_numbers(changeset) do
    Enum.reduce(
      [:capacity_kg, :gross_weight_kg, :seating_capacity],
      changeset,
      &validate_number(&2, &1, greater_than: 0)
    )
  end
end
