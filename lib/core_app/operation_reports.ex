defmodule CoreApp.OperationReports do
  @moduledoc """
  The OperationReports context.

  給油記録（`Refueling`）は日報に従属する子エンティティのため、専用のContextを作らず
  このContextで扱います。
  """

  import Ecto.Query, warn: false
  alias CoreApp.Repo
  alias Ecto.Multi

  alias CoreApp.OperationReports.OperationReport

  alias CoreApp.Accounts.Scope
  alias CoreApp.AuditLogs
  alias CoreApp.Utils.ConvertDatetime
  alias CoreApp.Utils.Pagination
  alias CoreApp.Vehicles.Vehicle

  @resource_type "operation_report"
  @preloads [:vehicle, :driver, :office, :refuelings, :created_by_user, :approved_by_user]

  @doc """
  ページネーションに対応した運行日報を取得します。運行日の降順で返します。

  一般利用者には自分が運転者の日報のみを返します。運転者台帳と紐付いていない場合は
  1件も返しません。

  ## params
  - `from` / `to` 運行日の期間（未指定時は当月）
  - `vehicle_id` 車両
  - `driver_id` 運転者（運行管理者以上のみ有効）
  - `status` ステータス
  - `office_id` 拠点（管理者のみ有効）
  - `page` / `page_size` ページネーション
  """
  def list_operation_reports(%Scope{} = scope, params \\ %{}) do
    {from_date, to_date} = period(params)

    OperationReport
    |> scoped(scope)
    |> where([r], r.operation_date >= ^from_date and r.operation_date <= ^to_date)
    |> filter_by_office(scope, params["office_id"])
    |> filter_by_vehicle(params["vehicle_id"])
    |> filter_by_driver(scope, params["driver_id"])
    |> filter_by_status(params["status"])
    |> order_by([r], desc: r.operation_date, desc: r.departed_at)
    |> preload(^@preloads)
    |> Pagination.paginate(params, Repo)
  end

  @doc """
  IDで運行日報を取得します。スコープの範囲外は `Ecto.NoResultsError` を発生させます。
  """
  def get_operation_report!(%Scope{} = scope, <<_::208>> = id) do
    OperationReport
    |> scoped(scope)
    |> preload(^@preloads)
    |> Repo.get!(id)
  end

  @doc """
  ステータスごとの日報の件数を返します。スコープの範囲内のみを数えます。
  """
  def count_reports_by_status(%Scope{} = scope) do
    OperationReport
    |> scoped(scope)
    |> group_by([r], r.status)
    |> select([r], {r.status, count(r.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  運行日報を作成します。給油記録も同一トランザクションで保存します（V-17）。
  """
  def create_operation_report(%Scope{} = scope, attrs \\ %{}) do
    %OperationReport{}
    |> change_operation_report(scope, attrs)
    |> Repo.insert()
  end

  @doc """
  運行日報を更新します。
  """
  def update_operation_report(%Scope{} = scope, %OperationReport{} = report, attrs) do
    report
    |> change_operation_report(scope, attrs)
    |> Repo.update()
  end

  @doc """
  運行日報のchangesetを取得します。

  オドメーターの逆転は、一般利用者にはエラー、運行管理者・管理者には警告として扱います（V-10）。
  """
  def change_operation_report(%OperationReport{} = report, %Scope{} = scope, attrs \\ %{}) do
    report
    |> OperationReport.changeset(defaults(scope, report, attrs), strict: strict?(scope))
    |> validate_office_scope(scope)
  end

  # 管理者以外は自拠点の車両でしか日報を作れない
  defp validate_office_scope(changeset, %Scope{role: :admin}), do: changeset

  defp validate_office_scope(changeset, %Scope{office_id: office_id}) do
    case Ecto.Changeset.get_field(changeset, :office_id) do
      nil -> changeset
      ^office_id -> changeset
      _other -> Ecto.Changeset.add_error(changeset, :vehicle_id, "は自拠点の車両を選択してください")
    end
  end

  @doc """
  下書きの運行日報を削除します。提出以降の日報は削除できません。
  """
  def delete_operation_report(%Scope{} = scope, %OperationReport{status: :draft} = report) do
    if editable?(scope, report), do: Repo.delete(report), else: {:error, :unauthorized}
  end

  def delete_operation_report(_scope, %OperationReport{}), do: {:error, :not_draft}

  @doc """
  保存はできるが確認すべき事項を返します（V-11・V-13）。

  DBの他レコードとの突き合わせが必要なため、changesetではなくここで判定します。
  """
  def warnings(%Scope{} = _scope, %Ecto.Changeset{} = changeset) do
    []
    |> odometer_gap_warning(changeset)
    |> odometer_order_warning(changeset)
    |> duplicate_operation_warning(changeset)
    |> Enum.reverse()
  end

  @doc """
  スコープが日報を編集できるかを返します。
  """
  def editable?(%Scope{role: :admin}, %OperationReport{}), do: true

  def editable?(%Scope{role: :manager, office_id: office_id}, %OperationReport{} = report) do
    report.office_id == office_id and report.status != :approved
  end

  def editable?(%Scope{role: :member, driver_id: driver_id}, %OperationReport{} = report) do
    report.driver_id == driver_id and report.status in [:draft, :rejected]
  end

  def editable?(_scope, _report), do: false

  @doc """
  日報を提出します。下書きと差戻しからのみ提出できます。
  """
  def submit_report(%Scope{} = scope, %OperationReport{} = report) do
    # 状態を先に判定する。提出済みの日報を再提出しようとした場合、
    # 「権限がない」ではなく「提出済みである」ことを返したいため。
    with :ok <- ensure_status(report, [:draft, :rejected]),
         :ok <- ensure_editable(scope, report) do
      report
      |> OperationReport.submit_changeset()
      |> Repo.update()
    end
  end

  @doc """
  日報を承認します。承認時に車両の最終オドメーターを更新し（V-18）、監査ログを記録します。
  """
  def approve_report(%Scope{} = scope, %OperationReport{} = report, opts \\ []) do
    with :ok <- ensure_manager(scope, report),
         :ok <- ensure_status(report, [:submitted]) do
      Multi.new()
      |> Multi.update(:report, OperationReport.approve_changeset(report, scope.user.id))
      |> Multi.run(:vehicle, &update_latest_odometer/2)
      |> AuditLogs.record_multi(
        :audit_log,
        scope,
        :approve,
        &{@resource_type, &1.report},
        opts
      )
      |> Repo.transaction()
      |> normalize_transaction()
    end
  end

  @doc """
  日報を差し戻します。理由は必須です（V-19）。
  """
  def reject_report(%Scope{} = scope, %OperationReport{} = report, reason, opts \\ []) do
    with :ok <- ensure_manager(scope, report),
         :ok <- ensure_status(report, [:submitted]) do
      Multi.new()
      |> Multi.update(:report, OperationReport.reject_changeset(report, reason))
      |> AuditLogs.record_multi(
        :audit_log,
        scope,
        :reject,
        &{@resource_type, &1.report},
        opts
      )
      |> Repo.transaction()
      |> normalize_transaction()
    end
  end

  # V-18: 承認済みの日報の帰着時オドメーターが現在値より大きい場合のみ更新する
  defp update_latest_odometer(repo, %{report: report}) do
    vehicle = repo.get!(Vehicle, report.vehicle_id)

    if is_nil(vehicle.latest_odometer) or report.end_odometer > vehicle.latest_odometer do
      vehicle
      |> Ecto.Changeset.change(latest_odometer: report.end_odometer)
      |> repo.update()
    else
      {:ok, vehicle}
    end
  end

  defp scoped(query, %Scope{role: :admin}), do: query

  defp scoped(query, %Scope{role: :manager, office_id: office_id}) do
    where(query, [r], r.office_id == ^office_id)
  end

  defp scoped(query, %Scope{role: :member, driver_id: nil}) do
    where(query, [r], false)
  end

  defp scoped(query, %Scope{role: :member, driver_id: driver_id}) do
    where(query, [r], r.driver_id == ^driver_id)
  end

  # 一般利用者は自分が運転者の日報しか作れない。
  defp defaults(%Scope{role: :member} = scope, report, attrs) do
    attrs
    |> convert_datetime_inputs()
    |> Map.put("driver_id", scope.driver_id)
    |> Map.put("created_by_user_id", created_by(report, scope))
    |> put_office_id(report, scope)
  end

  defp defaults(%Scope{} = scope, report, attrs) do
    attrs
    |> convert_datetime_inputs()
    |> Map.put("created_by_user_id", created_by(report, scope))
    |> put_office_id(report, scope)
  end

  # フォーム（datetime-local）から届く日時はJSTのため、UTCに変換してからcastする。
  defp convert_datetime_inputs(attrs) do
    attrs
    |> convert_key("departed_at")
    |> convert_key("returned_at")
    |> convert_refuelings()
  end

  defp convert_key(attrs, key) do
    case Map.fetch(attrs, key) do
      {:ok, value} -> Map.put(attrs, key, ConvertDatetime.parse_input(value))
      :error -> attrs
    end
  end

  defp convert_refuelings(attrs) do
    case Map.fetch(attrs, "refuelings") do
      {:ok, refuelings} when is_map(refuelings) ->
        Map.put(
          attrs,
          "refuelings",
          Map.new(refuelings, fn {index, refueling} ->
            {index, convert_key(refueling, "refueled_at")}
          end)
        )

      _other ->
        attrs
    end
  end

  # 日報の拠点は「車両の配置拠点」に従う。作成者の拠点ではない。
  # 管理者が他拠点の車両の日報を代理入力しても、その拠点の日報として扱うため。
  defp put_office_id(attrs, report, scope) do
    office_id =
      case vehicle_office_id(attrs["vehicle_id"] || attrs[:vehicle_id]) do
        nil -> report.office_id || scope.office_id
        office_id -> office_id
      end

    Map.put(attrs, "office_id", office_id)
  end

  defp vehicle_office_id(nil), do: nil
  defp vehicle_office_id(""), do: nil

  defp vehicle_office_id(<<_::208>> = vehicle_id) do
    Vehicle |> select([v], v.office_id) |> Repo.get(vehicle_id)
  end

  defp vehicle_office_id(_vehicle_id), do: nil

  defp created_by(%OperationReport{created_by_user_id: nil}, scope), do: scope.user.id
  defp created_by(%OperationReport{created_by_user_id: user_id}, _scope), do: user_id

  defp strict?(%Scope{role: :member}), do: true
  defp strict?(%Scope{}), do: false

  defp ensure_editable(scope, report) do
    if editable?(scope, report), do: :ok, else: {:error, :unauthorized}
  end

  defp ensure_manager(%Scope{role: role} = scope, report) when role in [:admin, :manager] do
    if role == :admin or report.office_id == scope.office_id do
      :ok
    else
      {:error, :unauthorized}
    end
  end

  defp ensure_manager(_scope, _report), do: {:error, :unauthorized}

  defp ensure_status(%OperationReport{status: status}, allowed) do
    if status in allowed, do: :ok, else: {:error, :invalid_status}
  end

  # V-11: 前回の帰着時オドメーターを下回っていないか
  defp odometer_gap_warning(warnings, changeset) do
    vehicle_id = Ecto.Changeset.get_field(changeset, :vehicle_id)
    start_odometer = Ecto.Changeset.get_field(changeset, :start_odometer)
    departed_at = Ecto.Changeset.get_field(changeset, :departed_at)
    report_id = Ecto.Changeset.get_field(changeset, :id)

    with false <- is_nil(vehicle_id) or is_nil(start_odometer) or is_nil(departed_at),
         %OperationReport{} = previous <- previous_report(vehicle_id, departed_at, report_id),
         true <- start_odometer < previous.end_odometer do
      [
        "前回の運行（#{Date.to_string(previous.operation_date)}）の帰着時 #{previous.end_odometer} km を下回っています。備考に理由を記入してください。"
        | warnings
      ]
    else
      _other -> warnings
    end
  end

  # V-10 を警告として扱う場合（運行管理者・管理者）の表示用
  defp odometer_order_warning(warnings, changeset) do
    start_odometer = Ecto.Changeset.get_field(changeset, :start_odometer)
    end_odometer = Ecto.Changeset.get_field(changeset, :end_odometer)

    if start_odometer && end_odometer && end_odometer < start_odometer do
      ["帰着時の走行距離計が出発時を下回っています。走行距離は0kmとして記録されます。" | warnings]
    else
      warnings
    end
  end

  # V-13: 同一車両・同一時間帯の日報が既にあるか
  defp duplicate_operation_warning(warnings, changeset) do
    vehicle_id = Ecto.Changeset.get_field(changeset, :vehicle_id)
    departed_at = Ecto.Changeset.get_field(changeset, :departed_at)
    returned_at = Ecto.Changeset.get_field(changeset, :returned_at)
    report_id = Ecto.Changeset.get_field(changeset, :id)

    with false <- is_nil(vehicle_id) or is_nil(departed_at) or is_nil(returned_at),
         true <- overlapping?(vehicle_id, departed_at, returned_at, report_id) do
      ["同じ車両で時間帯が重なる日報が既に登録されています。重複していないか確認してください。" | warnings]
    else
      _other -> warnings
    end
  end

  defp previous_report(vehicle_id, departed_at, report_id) do
    OperationReport
    |> where([r], r.vehicle_id == ^vehicle_id and r.returned_at <= ^departed_at)
    |> exclude_self(report_id)
    |> order_by([r], desc: r.returned_at)
    |> limit(1)
    |> Repo.one()
  end

  defp overlapping?(vehicle_id, departed_at, returned_at, report_id) do
    OperationReport
    |> where([r], r.vehicle_id == ^vehicle_id)
    |> where([r], r.departed_at < ^returned_at and r.returned_at > ^departed_at)
    |> exclude_self(report_id)
    |> Repo.exists?()
  end

  defp exclude_self(query, nil), do: query
  defp exclude_self(query, report_id), do: where(query, [r], r.id != ^report_id)

  defp period(params) do
    today = ConvertDatetime.today()

    {
      parse_date(params["from"]) || Date.beginning_of_month(today),
      parse_date(params["to"]) || Date.end_of_month(today)
    }
  end

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _error -> nil
    end
  end

  defp parse_date(%Date{} = date), do: date

  defp filter_by_office(query, %Scope{role: :admin}, office_id)
       when is_binary(office_id) and office_id != "" do
    where(query, [r], r.office_id == ^office_id)
  end

  defp filter_by_office(query, _scope, _office_id), do: query

  defp filter_by_vehicle(query, vehicle_id) when is_binary(vehicle_id) and vehicle_id != "" do
    where(query, [r], r.vehicle_id == ^vehicle_id)
  end

  defp filter_by_vehicle(query, _vehicle_id), do: query

  defp filter_by_driver(query, %Scope{role: :member}, _driver_id), do: query

  defp filter_by_driver(query, _scope, driver_id) when is_binary(driver_id) and driver_id != "" do
    where(query, [r], r.driver_id == ^driver_id)
  end

  defp filter_by_driver(query, _scope, _driver_id), do: query

  defp filter_by_status(query, status) when is_binary(status) and status != "" do
    where(query, [r], r.status == ^status)
  end

  defp filter_by_status(query, _status), do: query

  defp normalize_transaction({:ok, %{report: report}}), do: {:ok, report}
  defp normalize_transaction({:error, :report, changeset, _changes}), do: {:error, changeset}
end
