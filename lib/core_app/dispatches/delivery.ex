defmodule CoreApp.Dispatches.Delivery do
  @moduledoc false
  use CoreApp.Schema
  import Ecto.Changeset

  schema "dispatch_deliveries" do
    field :position, :integer, default: 0
    field :destination, :string
    field :fare_yen, :integer
    field :loading_at, :utc_datetime
    field :unloading_at, :utc_datetime

    field :dispatch_id, Ecto.ULID

    timestamps(type: :utc_datetime)
  end

  @doc """
  配送明細のchangesetです。

  配送料金は親の料金方式に従います。`:per_delivery` のときのみ必須で、
  `:course_total` のときは使わないため nil に正規化します（D-3）。
  表示順 `position` は入力順（0始まりの `index`）から1始まりで採番します。

  荷積み・荷降ろし日時は任意です（B-1）。両方あれば荷降ろしは荷積みより後（B-2）、
  入力された時刻は親の配送開始〜終了の範囲内（B-3）でなければなりません。
  親の日時が未入力のときは範囲を検証しません。
  """
  def changeset(delivery, attrs, index, pricing_type, started_at \\ nil, ended_at \\ nil) do
    delivery
    |> cast(attrs, [:destination, :fare_yen, :loading_at, :unloading_at])
    |> put_change(:position, index + 1)
    |> validate_required([:destination])
    |> validate_length(:destination, max: 255)
    |> validate_fare(pricing_type)
    |> validate_unloading_after_loading()
    |> validate_within(:loading_at, started_at, ended_at)
    |> validate_within(:unloading_at, started_at, ended_at)
  end

  # B-2: 荷降ろしは荷積みより後
  defp validate_unloading_after_loading(changeset) do
    loading_at = get_field(changeset, :loading_at)
    unloading_at = get_field(changeset, :unloading_at)

    if loading_at && unloading_at && !DateTime.after?(unloading_at, loading_at) do
      add_error(changeset, :unloading_at, "は荷積み日時より後の日時を入力してください")
    else
      changeset
    end
  end

  # B-3: 荷積み・荷降ろしは配送開始〜終了の範囲内（境界を含む）
  defp validate_within(changeset, _field, started_at, ended_at)
       when is_nil(started_at) or is_nil(ended_at),
       do: changeset

  # 値が変わっていなくても検証する（配車の時間を縮めたとき、既存の時刻が範囲外になるため）
  defp validate_within(changeset, field, started_at, ended_at) do
    value = get_field(changeset, field)

    if value && (DateTime.before?(value, started_at) or DateTime.after?(value, ended_at)) do
      add_error(changeset, field, "は配送開始〜終了の間の日時を入力してください")
    else
      changeset
    end
  end

  defp validate_fare(changeset, :per_delivery) do
    changeset
    |> validate_required([:fare_yen])
    |> validate_number(:fare_yen, greater_than_or_equal_to: 0)
  end

  defp validate_fare(changeset, _pricing_type), do: put_change(changeset, :fare_yen, nil)
end
