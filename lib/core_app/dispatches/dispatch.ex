defmodule CoreApp.Dispatches.Dispatch do
  @moduledoc false
  use CoreApp.Schema
  import Ecto.Changeset

  alias CoreApp.Accounts.User
  alias CoreApp.Dispatches.Delivery
  alias CoreApp.Drivers.Driver
  alias CoreApp.Offices.Office
  alias CoreApp.Shippers.Shipper
  alias CoreApp.Vehicles.Vehicle

  @pricing_types ~w(course_total per_delivery)a

  schema "dispatches" do
    field :title, :string
    field :description, :string
    field :started_at, :utc_datetime
    field :ended_at, :utc_datetime
    field :pricing_type, Ecto.Enum, values: @pricing_types, default: :course_total
    field :course_fare_yen, :integer
    field :toll_yen, :integer, default: 0

    belongs_to(:office, Office)
    belongs_to(:shipper, Shipper)
    belongs_to(:vehicle, Vehicle)
    belongs_to(:driver, Driver)
    belongs_to(:created_by_user, User)

    has_many :deliveries, Delivery, on_replace: :delete, preload_order: [asc: :position]

    timestamps(type: :utc_datetime)
  end

  @doc """
  料金方式の一覧を返します。
  """
  def pricing_types, do: @pricing_types

  @doc """
  受取金額の合計（円）を返します（D-2）。

  - コース一括: コース料金 + 高速料金
  - 配送ごと: 配送料金の合計 + 高速料金
  """
  def total_amount_yen(%__MODULE__{} = dispatch) do
    fare_total_yen(dispatch) + (dispatch.toll_yen || 0)
  end

  @doc """
  運賃（高速料金を除く）の合計（円）を返します。
  """
  def fare_total_yen(%__MODULE__{pricing_type: :per_delivery, deliveries: deliveries})
      when is_list(deliveries) do
    fare_yen(:per_delivery, nil, deliveries |> Enum.map(&(&1.fare_yen || 0)) |> Enum.sum())
  end

  def fare_total_yen(%__MODULE__{pricing_type: :course_total, course_fare_yen: fare}) do
    fare_yen(:course_total, fare, nil)
  end

  def fare_total_yen(%__MODULE__{}), do: 0

  @doc """
  料金方式に応じた運賃（高速料金を除く）を返します（D-2）。

  DBで集計した値（CSV出力など、`Dispatch` の構造体を作らない場合）でも同じ規則で計算できるよう、
  構造体から切り離した関数にしています。

  - `:course_total` はコース料金
  - `:per_delivery` は配送明細の配送料金の合計
  """
  def fare_yen(:course_total, course_fare_yen, _deliveries_fare_total), do: course_fare_yen || 0

  def fare_yen(:per_delivery, _course_fare_yen, deliveries_fare_total),
    do: deliveries_fare_total || 0

  def changeset(dispatch, attrs) do
    changeset =
      cast(dispatch, attrs, [
        :office_id,
        :shipper_id,
        :vehicle_id,
        :driver_id,
        :created_by_user_id,
        :title,
        :description,
        :started_at,
        :ended_at,
        :pricing_type,
        :course_fare_yen,
        :toll_yen
      ])

    pricing_type = get_field(changeset, :pricing_type)
    started_at = get_field(changeset, :started_at)
    ended_at = get_field(changeset, :ended_at)

    changeset
    |> cast_assoc(:deliveries,
      with: &Delivery.changeset(&1, &2, &3, pricing_type, started_at, ended_at),
      sort_param: :deliveries_sort,
      drop_param: :deliveries_drop
    )
    |> validate_required([
      :office_id,
      :shipper_id,
      :vehicle_id,
      :driver_id,
      :created_by_user_id,
      :title,
      :started_at,
      :ended_at,
      :pricing_type
    ])
    |> validate_length(:title, max: 255)
    |> validate_number(:toll_yen, greater_than_or_equal_to: 0)
    |> put_toll_default()
    |> validate_ended_after_started()
    |> validate_pricing(pricing_type)
    |> assoc_constraint(:office)
    |> assoc_constraint(:shipper)
    |> assoc_constraint(:vehicle)
    |> assoc_constraint(:driver)
  end

  # 高速料金が未入力（空欄）の場合は0円として扱う
  defp put_toll_default(changeset) do
    if is_nil(get_field(changeset, :toll_yen)),
      do: put_change(changeset, :toll_yen, 0),
      else: changeset
  end

  # D-1: 終了日時は開始日時より後
  defp validate_ended_after_started(changeset) do
    started_at = get_field(changeset, :started_at)
    ended_at = get_field(changeset, :ended_at)

    if started_at && ended_at && !DateTime.after?(ended_at, started_at) do
      add_error(changeset, :ended_at, "は配送開始日時より後の日時を入力してください")
    else
      changeset
    end
  end

  # D-2・D-3: 料金方式に応じて必須項目を切り替え、使わない側の金額は nil に正規化する
  defp validate_pricing(changeset, :course_total) do
    changeset
    |> validate_required([:course_fare_yen], message: "コース料金を入力してください")
    |> validate_number(:course_fare_yen, greater_than_or_equal_to: 0)
  end

  defp validate_pricing(changeset, :per_delivery) do
    changeset = put_change(changeset, :course_fare_yen, nil)

    if active_deliveries(changeset) == [] do
      add_error(changeset, :deliveries, "を1件以上入力してください")
    else
      changeset
    end
  end

  defp validate_pricing(changeset, _pricing_type), do: changeset

  defp active_deliveries(changeset) do
    changeset
    |> get_assoc(:deliveries)
    |> Enum.reject(&(&1.action in [:replace, :delete]))
  end
end
