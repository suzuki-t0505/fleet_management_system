defmodule CoreApp.Drivers.Driver do
  @moduledoc false
  use CoreApp.Schema
  import Ecto.Changeset

  alias CoreApp.Accounts.User
  alias CoreApp.Offices.Office
  alias CoreApp.Utils.ConvertDatetime

  @employment_types ~w(full_time contract part_time other retired)a
  @license_types ~w(large medium semi_medium ordinary large_special towing)a

  schema "drivers" do
    field :code, :string
    field :name, :string
    field :name_kana, :string
    field :employment_type, Ecto.Enum, values: @employment_types
    field :hired_on, :date
    field :retired_on, :date

    field :license_number, :string
    field :license_types, {:array, Ecto.Enum}, values: @license_types
    field :license_expires_on, :date

    field :note, :string

    belongs_to(:office, Office)
    belongs_to(:user, User)

    timestamps(type: :utc_datetime)
  end

  @doc """
  雇用区分の一覧を返します。
  """
  def employment_types, do: @employment_types

  @doc """
  免許種類の一覧を返します。
  """
  def license_types, do: @license_types

  @doc """
  免許証の有効期限が切れているかを返します。
  """
  def license_expired?(%__MODULE__{license_expires_on: nil}), do: false

  def license_expired?(%__MODULE__{license_expires_on: date}) do
    ConvertDatetime.days_until(date) < 0
  end

  def changeset(driver, attrs) do
    driver
    |> cast(attrs, [
      :office_id,
      :user_id,
      :code,
      :name,
      :name_kana,
      :employment_type,
      :hired_on,
      :retired_on,
      :license_number,
      :license_types,
      :license_expires_on,
      :note
    ])
    |> validate_required([
      :office_id,
      :code,
      :name,
      :name_kana,
      :employment_type,
      :hired_on,
      :license_number,
      :license_expires_on
    ])
    |> validate_length(:code, max: 20)
    |> validate_length(:name, max: 100)
    |> validate_length(:name_kana, max: 100)
    |> validate_length(:license_number, max: 20)
    |> validate_license_types()
    |> validate_hired_on()
    |> validate_retirement()
    |> unique_constraint(:code, message: "この運転者コードは既に登録されています")
    |> unique_constraint(:user_id, message: "このアカウントは既に他の運転者に紐付いています")
    |> assoc_constraint(:office)
    |> assoc_constraint(:user)
  end

  # 追加2: 免許種類は1つ以上
  defp validate_license_types(changeset) do
    case get_field(changeset, :license_types) do
      types when is_list(types) and types != [] -> changeset
      _other -> add_error(changeset, :license_types, "を1つ以上選択してください")
    end
  end

  # 追加3: 入社年月日に未来日は入力できない
  defp validate_hired_on(changeset) do
    validate_change(changeset, :hired_on, fn :hired_on, value ->
      if Date.after?(value, ConvertDatetime.today()) do
        [hired_on: "に未来の日付は入力できません"]
      else
        []
      end
    end)
  end

  # 追加4・追加5: 退職年月日は入社年月日以降で、雇用区分が「退職」であること
  defp validate_retirement(changeset) do
    retired_on = get_field(changeset, :retired_on)
    hired_on = get_field(changeset, :hired_on)
    employment_type = get_field(changeset, :employment_type)

    changeset
    |> validate_retired_after_hired(retired_on, hired_on)
    |> validate_retired_employment_type(retired_on, employment_type)
  end

  defp validate_retired_after_hired(changeset, nil, _hired_on), do: changeset
  defp validate_retired_after_hired(changeset, _retired_on, nil), do: changeset

  defp validate_retired_after_hired(changeset, retired_on, hired_on) do
    if Date.before?(retired_on, hired_on) do
      add_error(changeset, :retired_on, "は入社年月日より後の日付を入力してください")
    else
      changeset
    end
  end

  defp validate_retired_employment_type(changeset, nil, _employment_type), do: changeset
  defp validate_retired_employment_type(changeset, _retired_on, :retired), do: changeset

  defp validate_retired_employment_type(changeset, _retired_on, _employment_type) do
    add_error(changeset, :employment_type, "は退職年月日を入力する場合「退職」にしてください")
  end
end
