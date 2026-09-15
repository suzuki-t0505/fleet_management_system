defmodule CoreApp.Reports do
  @moduledoc """
  The Reports context.

  集計クエリだけを持つ読み取り専用のContextです。スキーマは持ちません。

  集計対象は**承認済みの日報のみ**（functional-design.md 8.2）。月は JST の
  運行日・実施日・発生日で切ります。
  """

  import Ecto.Query, warn: false
  alias CoreApp.Repo

  alias CoreApp.Accounts.Scope
  alias CoreApp.Incidents.Incident
  alias CoreApp.Maintenances.Maintenance
  alias CoreApp.Offices.Office
  alias CoreApp.OperationReports.OperationReport
  alias CoreApp.OperationReports.Refueling
  alias CoreApp.Utils.ConvertDatetime
  alias CoreApp.Utils.Pagination

  # 既定で集計する月数
  @default_months 6

  # CSV出力時に打ち切る行数
  @max_export_rows 50_000

  @report_types ~w(distance fuel maintenance_cost incident)a

  # 日付を月初に丸める（JSTの日付カラムに対して使う）
  defmacrop month_of(field) do
    quote do: fragment("date_trunc('month', ?)::date", unquote(field))
  end

  @doc """
  走行距離を月 × 軸で集計します。

  ## params
  - `from` / `to` 集計する月（`YYYY-MM`）。既定は直近 #{@default_months} ヶ月
  - `axis` 集計軸（`vehicle` / `driver` / `office`。既定は `vehicle`）
  - `office_id` 拠点（管理者のみ有効）
  - `page` / `page_size` ページネーション
  """
  def distance_report(%Scope{} = scope, params \\ %{}), do: paginated(scope, :distance, params)

  @doc """
  燃費を月 × 車両で集計します。給油が無い月の燃費は `nil` になります。
  """
  def fuel_report(%Scope{} = scope, params \\ %{}), do: paginated(scope, :fuel, params)

  @doc """
  整備費を月 × 軸 × 区分で集計します。区分ごとの行を返すため、種別の内訳がそのまま読めます。

  ## params
  - `axis` 集計軸（`vehicle` / `office`。既定は `vehicle`）
  """
  def maintenance_cost_report(%Scope{} = scope, params \\ %{}) do
    paginated(scope, :maintenance_cost, params)
  end

  @doc """
  事故・ヒヤリを月 × 拠点 × 区分で集計し、改善報告の完了率を算出します。
  """
  def incident_report(%Scope{} = scope, params \\ %{}), do: paginated(scope, :incident, params)

  @doc """
  集計結果をページネーションせずにすべて返します。CSV出力に使います。

  集計後の行数は「月数 × 対象数」に収まりますが、念のため #{@max_export_rows} 行で打ち切ります。
  """
  def all_report_rows(%Scope{} = scope, report, params \\ %{}) do
    scope
    |> rows_query(report, params)
    |> limit(^@max_export_rows)
    |> Repo.all()
    |> Enum.map(&post_process(report, &1))
  end

  @doc """
  集計の種類の一覧を返します。
  """
  def report_types, do: @report_types

  defp paginated(scope, report, params) do
    page =
      scope
      |> rows_query(report, params)
      |> Pagination.paginate(params, Repo)

    %{page | entries: Enum.map(page.entries, &post_process(report, &1))}
  end

  defp rows_query(scope, :distance, params) do
    {from, to} = period(params)

    OperationReport
    |> where([r], r.status == :approved)
    |> where([r], r.operation_date >= ^from and r.operation_date <= ^to)
    |> scoped_reports(scope)
    |> filter_reports_by_office(scope, params["office_id"])
    |> distance_grouped(axis(params, :vehicle))
    |> ordered_rows()
  end

  defp rows_query(scope, :fuel, params) do
    {from, to} = period(params)

    refuelings =
      from(f in Refueling,
        group_by: f.operation_report_id,
        select: %{
          report_id: f.operation_report_id,
          liters: sum(f.liters),
          amount_yen: sum(f.amount_yen)
        }
      )

    OperationReport
    |> where([r], r.status == :approved)
    |> where([r], r.operation_date >= ^from and r.operation_date <= ^to)
    |> scoped_reports(scope)
    |> filter_reports_by_office(scope, params["office_id"])
    |> join(:inner, [r], v in assoc(r, :vehicle), as: :vehicle)
    |> join(:left, [r], f in subquery(refuelings), on: f.report_id == r.id, as: :refueling)
    |> group_by([r, vehicle: v], [month_of(r.operation_date), v.id, v.plate_number])
    |> select([r, vehicle: v, refueling: f], %{
      month: month_of(r.operation_date),
      key_id: v.id,
      key_name: v.plate_number,
      distance_km: sum(r.distance_km),
      liters: sum(f.liters),
      amount_yen: sum(f.amount_yen)
    })
    |> ordered_rows()
  end

  defp rows_query(scope, :maintenance_cost, params) do
    {from, to} = period(params)

    Maintenance
    |> where([m], m.performed_on >= ^from and m.performed_on <= ^to)
    |> scoped_maintenances(scope)
    |> filter_maintenances_by_office(scope, params["office_id"])
    |> cost_grouped(axis(params, :vehicle))
    |> ordered_rows()
  end

  defp rows_query(scope, :incident, params) do
    {from, to} = period(params)

    Incident
    |> where([i], fragment("(? + interval '9 hours')::date", i.occurred_at) >= ^from)
    |> where([i], fragment("(? + interval '9 hours')::date", i.occurred_at) <= ^to)
    |> scoped_incidents(scope)
    |> filter_incidents_by_office(scope, params["office_id"])
    |> join(:inner, [i], o in assoc(i, :office), as: :office)
    |> group_by([i, office: o], [
      fragment("date_trunc('month', (? + interval '9 hours'))::date", i.occurred_at),
      o.id,
      o.name,
      i.category
    ])
    |> select([i, office: o], %{
      month: fragment("date_trunc('month', (? + interval '9 hours'))::date", i.occurred_at),
      key_id: o.id,
      key_name: o.name,
      category: i.category,
      total_count: count(i.id),
      closed_count: filter(count(i.id), i.status == :closed)
    })
    |> ordered_rows()
  end

  defp post_process(:fuel, row), do: put_km_per_liter(row)
  defp post_process(:incident, row), do: put_completion_rate(row)
  defp post_process(_report, row), do: row

  @doc """
  当月の稼働車両台数と総走行距離を返します。承認済みの日報だけを数えます。
  """
  def monthly_activity(%Scope{} = scope, %Date{} = today \\ ConvertDatetime.today()) do
    from_date = Date.beginning_of_month(today)
    to_date = Date.end_of_month(today)

    OperationReport
    |> where([r], r.status == :approved)
    |> where([r], r.operation_date >= ^from_date and r.operation_date <= ^to_date)
    |> scoped_reports(scope)
    |> select([r], %{
      active_vehicles: fragment("count(distinct ?)", r.vehicle_id),
      distance_km: coalesce(sum(r.distance_km), 0)
    })
    |> Repo.one()
  end

  @doc """
  拠点別の内訳を返します。管理者のダッシュボードで使います。

  各拠点の当月の走行距離と、未承認の日報・未完了の改善報告の件数を返します。
  """
  def office_summaries(%Scope{role: :admin} = scope, %Date{} = today \\ ConvertDatetime.today()) do
    from_date = Date.beginning_of_month(today)
    to_date = Date.end_of_month(today)

    distances = distances_by_office(scope, from_date, to_date)
    submitted = counts_by_office(OperationReport, scope, dynamic([r], r.status == :submitted))
    open_incidents = counts_by_office(Incident, scope, dynamic([i], i.status != :closed))

    Office
    |> where([o], o.active == true)
    |> order_by([o], asc: o.code)
    |> Repo.all()
    |> Enum.map(fn office ->
      %{
        office: office,
        distance_km: Map.get(distances, office.id, 0),
        submitted_reports: Map.get(submitted, office.id, 0),
        open_incidents: Map.get(open_incidents, office.id, 0)
      }
    end)
  end

  @doc """
  集計軸として選べる値を返します。
  """
  def axes, do: [:vehicle, :driver, :office]

  @doc """
  既定で集計する月数を返します。
  """
  def default_months, do: @default_months

  defp distances_by_office(scope, from_date, to_date) do
    OperationReport
    |> where([r], r.status == :approved)
    |> where([r], r.operation_date >= ^from_date and r.operation_date <= ^to_date)
    |> scoped_reports(scope)
    |> group_by([r], r.office_id)
    |> select([r], {r.office_id, coalesce(sum(r.distance_km), 0)})
    |> Repo.all()
    |> Map.new()
  end

  defp counts_by_office(schema, scope, condition) do
    schema
    |> where(^condition)
    |> scoped_office(scope)
    |> group_by([x], x.office_id)
    |> select([x], {x.office_id, count(x.id)})
    |> Repo.all()
    |> Map.new()
  end

  # 走行距離の集計軸。稼働日数は日報の件数ではなく運行日の異なり数で数える。
  defp distance_grouped(query, :vehicle) do
    query
    |> join(:inner, [r], v in assoc(r, :vehicle), as: :key)
    |> group_by([r, key: k], [month_of(r.operation_date), k.id, k.plate_number])
    |> select([r, key: k], %{
      month: month_of(r.operation_date),
      key_id: k.id,
      key_name: k.plate_number,
      distance_km: coalesce(sum(r.distance_km), 0),
      operating_days: fragment("count(distinct ?)", r.operation_date),
      report_count: count(r.id)
    })
  end

  defp distance_grouped(query, :driver) do
    query
    |> join(:inner, [r], d in assoc(r, :driver), as: :key)
    |> group_by([r, key: k], [month_of(r.operation_date), k.id, k.name])
    |> select([r, key: k], %{
      month: month_of(r.operation_date),
      key_id: k.id,
      key_name: k.name,
      distance_km: coalesce(sum(r.distance_km), 0),
      operating_days: fragment("count(distinct ?)", r.operation_date),
      report_count: count(r.id)
    })
  end

  defp distance_grouped(query, :office) do
    query
    |> join(:inner, [r], o in assoc(r, :office), as: :key)
    |> group_by([r, key: k], [month_of(r.operation_date), k.id, k.name])
    |> select([r, key: k], %{
      month: month_of(r.operation_date),
      key_id: k.id,
      key_name: k.name,
      distance_km: coalesce(sum(r.distance_km), 0),
      operating_days: fragment("count(distinct ?)", r.operation_date),
      report_count: count(r.id)
    })
  end

  defp cost_grouped(query, :office) do
    query
    |> join(:inner, [m], o in assoc(m, :office), as: :key)
    |> group_by([m, key: k], [month_of(m.performed_on), k.id, k.name, m.category])
    |> select([m, key: k], %{
      month: month_of(m.performed_on),
      key_id: k.id,
      key_name: k.name,
      category: m.category,
      cost_yen: coalesce(sum(m.cost_yen), 0),
      maintenance_count: count(m.id)
    })
  end

  defp cost_grouped(query, _axis) do
    query
    |> join(:inner, [m], v in assoc(m, :vehicle), as: :key)
    |> group_by([m, key: k], [month_of(m.performed_on), k.id, k.plate_number, m.category])
    |> select([m, key: k], %{
      month: month_of(m.performed_on),
      key_id: k.id,
      key_name: k.plate_number,
      category: m.category,
      cost_yen: coalesce(sum(m.cost_yen), 0),
      maintenance_count: count(m.id)
    })
  end

  # group_by したクエリはそのまま数えると「グループごとの件数」が返るため、
  # subquery で包んでから並べ替える。
  defp ordered_rows(query) do
    from(row in subquery(query), order_by: [desc: row.month, asc: row.key_name])
  end

  defp put_km_per_liter(%{liters: liters, distance_km: distance_km} = row) do
    Map.put(row, :km_per_liter, km_per_liter(distance_km, liters))
  end

  defp km_per_liter(_distance_km, nil), do: nil

  defp km_per_liter(distance_km, liters) do
    liters = Decimal.new(liters)

    if Decimal.positive?(liters) do
      distance_km |> Decimal.new() |> Decimal.div(liters) |> Decimal.round(2)
    end
  end

  defp put_completion_rate(%{total_count: total, closed_count: closed} = row) do
    Map.put(row, :completion_rate, completion_rate(total, closed))
  end

  defp completion_rate(0, _closed), do: nil
  defp completion_rate(total, closed), do: round(closed / total * 100)

  defp period(params) do
    today = ConvertDatetime.today()
    default_from = today |> Date.beginning_of_month() |> shift_months(-(@default_months - 1))

    from = parse_month(params["from"]) || default_from
    to = (parse_month(params["to"]) || Date.beginning_of_month(today)) |> Date.end_of_month()

    {from, to}
  end

  defp shift_months(%Date{} = date, months) do
    date
    |> Date.add(months * 31)
    |> Date.beginning_of_month()
  end

  defp parse_month(value) when is_binary(value) and value != "" do
    case Date.from_iso8601(value <> "-01") do
      {:ok, date} -> date
      _error -> nil
    end
  end

  defp parse_month(_value), do: nil

  defp axis(params, default) do
    case params["axis"] do
      "vehicle" -> :vehicle
      "driver" -> :driver
      "office" -> :office
      _other -> default
    end
  end

  defp scoped_reports(query, %Scope{role: :admin}), do: query

  defp scoped_reports(query, %Scope{office_id: office_id}) do
    where(query, [r], r.office_id == ^office_id)
  end

  defp scoped_maintenances(query, %Scope{role: :admin}), do: query

  defp scoped_maintenances(query, %Scope{office_id: office_id}) do
    where(query, [m], m.office_id == ^office_id)
  end

  # 事故・ヒヤリの集計は自拠点のみを対象にする。全社共有された他拠点の記録は
  # 参照はできるが、自拠点の統計に混ぜない。
  defp scoped_incidents(query, %Scope{role: :admin}), do: query

  defp scoped_incidents(query, %Scope{office_id: office_id}) do
    where(query, [i], i.office_id == ^office_id)
  end

  defp scoped_office(query, %Scope{role: :admin}), do: query

  defp scoped_office(query, %Scope{office_id: office_id}) do
    where(query, [x], x.office_id == ^office_id)
  end

  defp filter_reports_by_office(query, %Scope{role: :admin}, office_id)
       when is_binary(office_id) and office_id != "" do
    where(query, [r], r.office_id == ^office_id)
  end

  defp filter_reports_by_office(query, _scope, _office_id), do: query

  defp filter_maintenances_by_office(query, %Scope{role: :admin}, office_id)
       when is_binary(office_id) and office_id != "" do
    where(query, [m], m.office_id == ^office_id)
  end

  defp filter_maintenances_by_office(query, _scope, _office_id), do: query

  defp filter_incidents_by_office(query, %Scope{role: :admin}, office_id)
       when is_binary(office_id) and office_id != "" do
    where(query, [i], i.office_id == ^office_id)
  end

  defp filter_incidents_by_office(query, _scope, _office_id), do: query
end
