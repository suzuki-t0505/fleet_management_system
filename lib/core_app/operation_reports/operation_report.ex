defmodule CoreApp.OperationReports.OperationReport do
  @moduledoc false
  use CoreApp.Schema
  import Ecto.Changeset

  alias CoreApp.Accounts.User
  alias CoreApp.Drivers.Driver
  alias CoreApp.Offices.Office
  alias CoreApp.OperationReports.Refueling
  alias CoreApp.Utils.ConvertDatetime
  alias CoreApp.Vehicles.Vehicle

  @statuses ~w(draft submitted approved rejected)a

  schema "operation_reports" do
    field :operation_date, :date
    field :departed_at, :utc_datetime
    field :returned_at, :utc_datetime
    field :start_odometer, :integer
    field :end_odometer, :integer
    field :distance_km, :integer

    field :destination, :string
    field :cargo_type, :string
    field :rest_minutes, :integer

    field :status, Ecto.Enum, values: @statuses, default: :draft
    field :submitted_at, :utc_datetime
    field :approved_at, :utc_datetime
    field :rejected_reason, :string
    field :note, :string

    belongs_to(:office, Office)
    belongs_to(:vehicle, Vehicle)
    belongs_to(:driver, Driver)
    belongs_to(:created_by_user, User)
    belongs_to(:approved_by_user, User)

    has_many(:refuelings, Refueling, on_replace: :delete)

    timestamps(type: :utc_datetime)
  end

  @doc """
  日報のステータス一覧を返します。
  """
  def statuses, do: @statuses

  @doc """
  日報のchangesetです。

  ## options
  - `strict` オドメーターの逆転をエラーにするか（既定 `true`）。
    運行管理者・管理者は `false` を渡し、備考を添えて保存できる（V-10）。
  """
  def changeset(report, attrs, opts \\ []) do
    report
    |> cast(attrs, [
      :office_id,
      :vehicle_id,
      :driver_id,
      :created_by_user_id,
      :operation_date,
      :departed_at,
      :returned_at,
      :start_odometer,
      :end_odometer,
      :destination,
      :cargo_type,
      :rest_minutes,
      :note
    ])
    |> cast_assoc(:refuelings, sort_param: :refuelings_sort, drop_param: :refuelings_drop)
    |> validate_required([
      :office_id,
      :vehicle_id,
      :driver_id,
      :created_by_user_id,
      :operation_date,
      :departed_at,
      :returned_at,
      :start_odometer,
      :end_odometer
    ])
    |> validate_number(:start_odometer, greater_than_or_equal_to: 0)
    |> validate_number(:end_odometer, greater_than_or_equal_to: 0)
    |> validate_returned_after_departed()
    |> validate_operation_date()
    |> validate_rest_minutes()
    |> validate_odometer_order(Keyword.get(opts, :strict, true))
    |> validate_refuelings_within_operation()
    |> put_distance_km()
    |> assoc_constraint(:office)
    |> assoc_constraint(:vehicle)
    |> assoc_constraint(:driver)
  end

  @doc """
  提出のchangesetです。下書きと差戻しからのみ提出できます。
  """
  def submit_changeset(report) do
    change(report,
      status: :submitted,
      submitted_at: DateTime.utc_now(:second),
      rejected_reason: nil
    )
  end

  @doc """
  承認のchangesetです。
  """
  def approve_changeset(report, approver_id) do
    change(report,
      status: :approved,
      approved_at: DateTime.utc_now(:second),
      approved_by_user_id: approver_id
    )
  end

  @doc """
  差戻しのchangesetです。理由は必須です（V-19）。
  """
  def reject_changeset(report, reason) do
    report
    |> change(status: :rejected, approved_at: nil, approved_by_user_id: nil)
    |> cast(%{rejected_reason: reason}, [:rejected_reason])
    |> validate_required([:rejected_reason], message: "差戻しの理由を入力してください")
  end

  # V-9: 帰着日時は出発日時より後
  defp validate_returned_after_departed(changeset) do
    departed_at = get_field(changeset, :departed_at)
    returned_at = get_field(changeset, :returned_at)

    if departed_at && returned_at && !DateTime.after?(returned_at, departed_at) do
      add_error(changeset, :returned_at, "は出発日時より後の日時を入力してください")
    else
      changeset
    end
  end

  # V-14・追加1: 運行日は未来日不可。出発日または帰着日（JST）と一致すること
  defp validate_operation_date(changeset) do
    operation_date = get_field(changeset, :operation_date)
    departed_at = get_field(changeset, :departed_at)
    returned_at = get_field(changeset, :returned_at)

    changeset
    |> validate_not_future(operation_date)
    |> validate_matches_operation_days(operation_date, departed_at, returned_at)
  end

  defp validate_not_future(changeset, nil), do: changeset

  defp validate_not_future(changeset, operation_date) do
    if Date.after?(operation_date, ConvertDatetime.today()) do
      add_error(changeset, :operation_date, "に未来の日付は入力できません")
    else
      changeset
    end
  end

  defp validate_matches_operation_days(changeset, nil, _departed_at, _returned_at), do: changeset

  defp validate_matches_operation_days(changeset, _operation_date, nil, _returned_at),
    do: changeset

  defp validate_matches_operation_days(changeset, operation_date, departed_at, returned_at) do
    allowed =
      [departed_at, returned_at]
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&(&1 |> ConvertDatetime.to_jst() |> DateTime.to_date()))

    if operation_date in allowed do
      changeset
    else
      add_error(changeset, :operation_date, "は出発日または帰着日と同じ日付にしてください")
    end
  end

  # V-15: 休憩時間は0以上、運行時間未満
  defp validate_rest_minutes(changeset) do
    changeset = validate_number(changeset, :rest_minutes, greater_than_or_equal_to: 0)

    rest_minutes = get_field(changeset, :rest_minutes)
    departed_at = get_field(changeset, :departed_at)
    returned_at = get_field(changeset, :returned_at)

    if rest_minutes && departed_at && returned_at do
      operation_minutes = div(DateTime.diff(returned_at, departed_at), 60)

      if rest_minutes >= operation_minutes do
        add_error(changeset, :rest_minutes, "は運行時間（#{operation_minutes}分）未満にしてください")
      else
        changeset
      end
    else
      changeset
    end
  end

  # V-10: オドメーターの逆転。運転者はエラー、運行管理者は警告（保存可）
  defp validate_odometer_order(changeset, false), do: changeset

  defp validate_odometer_order(changeset, true) do
    start_odometer = get_field(changeset, :start_odometer)
    end_odometer = get_field(changeset, :end_odometer)

    if start_odometer && end_odometer && end_odometer < start_odometer do
      add_error(changeset, :end_odometer, "は出発時の走行距離計以上の値を入力してください")
    else
      changeset
    end
  end

  # 追加2: 給油日時は運行時間の範囲内
  defp validate_refuelings_within_operation(changeset) do
    departed_at = get_field(changeset, :departed_at)
    returned_at = get_field(changeset, :returned_at)

    update_change(changeset, :refuelings, fn refuelings ->
      Enum.map(refuelings, &Refueling.validate_within_operation(&1, departed_at, returned_at))
    end)
  end

  # V-12: 走行距離は算出する。パラメータで渡された値は使わない。
  # 逆転している場合（運行管理者が保存するとき）は0kmとして記録し、集計を壊さないようにする。
  defp put_distance_km(changeset) do
    start_odometer = get_field(changeset, :start_odometer)
    end_odometer = get_field(changeset, :end_odometer)

    if start_odometer && end_odometer do
      put_change(changeset, :distance_km, max(end_odometer - start_odometer, 0))
    else
      changeset
    end
  end
end
