defmodule CoreApp.Exports do
  @moduledoc """
  The Exports context.

  CSV出力のための行を返す読み取り専用のContextです。スキーマは持ちません。

  一覧画面が `preload` で組み立てる形と違い、CSVは**平坦な列**が要ります
  （`Repo.stream/2` は preload を実行できません）。そのため一覧とは別に、
  join と `select` で平坦なマップを返すクエリをここに置きます。
  絞り込みのパラメータ名は一覧と同じにそろえています。
  """

  import Ecto.Query, warn: false
  alias CoreApp.Repo

  alias CoreApp.Accounts.Scope
  alias CoreApp.Drivers.Driver
  alias CoreApp.Incidents.Incident
  alias CoreApp.Maintenances.Maintenance
  alias CoreApp.OperationReports.OperationReport
  alias CoreApp.Vehicles.Vehicle

  # 9.2: 出力上限。超えた場合は出力せず、絞り込みを促す
  @default_max_rows 50_000

  @resources ~w(vehicles drivers operation_reports maintenances incidents)a

  @doc """
  出力できるリソースの一覧を返します。
  """
  def resources, do: @resources

  @doc """
  1回の出力で許す最大行数を返します。

  運用で調整できるよう設定から読みます（既定 #{@default_max_rows}）。
  """
  def max_rows, do: Application.get_env(:core_app, :csv_max_rows, @default_max_rows)

  @doc """
  出力対象の行数を返します。上限の判定に使います。
  """
  def count(%Scope{} = scope, resource, params \\ %{}) do
    scope
    |> query(resource, params)
    |> exclude(:select)
    |> exclude(:order_by)
    |> Repo.aggregate(:count)
  end

  @doc """
  出力対象の行をストリームで渡します。

  全件をメモリに載せないため `Repo.stream/2` を使います。ストリームはトランザクション内
  でしか読めないため、呼び出し側の処理を関数で受け取ります。

  ```elixir
  iex> stream_rows(scope, :vehicles, params, fn rows -> Enum.count(rows) end)
  {:ok, 12}
  ```
  """
  def stream_rows(%Scope{} = scope, resource, params, fun) when is_function(fun, 1) do
    Repo.transaction(
      fn ->
        scope
        |> query(resource, params)
        |> Repo.stream(max_rows: 500)
        |> fun.()
      end,
      timeout: :infinity
    )
  end

  defp query(scope, :vehicles, params) do
    Vehicle
    |> join(:inner, [v], o in assoc(v, :office), as: :office)
    |> scoped(scope)
    |> filter_office(scope, params["office_id"])
    |> filter_vehicle_status(params["status"])
    |> filter_eq(:vehicle_class, params["vehicle_class"])
    |> search([:plate_number, :model_name], params["q"])
    |> order_by([v], asc: v.plate_number)
    |> select([v, office: o], %{
      plate_number: v.plate_number,
      vin: v.vin,
      vehicle_class: v.vehicle_class,
      maker: v.maker,
      model_name: v.model_name,
      first_registered_on: v.first_registered_on,
      status: v.status,
      office_name: o.name,
      inspection_expires_on: v.inspection_expires_on,
      liability_insurance_expires_on: v.liability_insurance_expires_on,
      voluntary_insurance_expires_on: v.voluntary_insurance_expires_on,
      next_periodic_3m_on: v.next_periodic_3m_on,
      next_periodic_12m_on: v.next_periodic_12m_on,
      latest_odometer: v.latest_odometer,
      note: v.note
    })
  end

  defp query(scope, :drivers, params) do
    Driver
    |> join(:inner, [d], o in assoc(d, :office), as: :office)
    |> scoped(scope)
    |> filter_office(scope, params["office_id"])
    |> filter_employment_type(params["employment_type"])
    |> search([:name, :name_kana, :code], params["q"])
    |> order_by([d], asc: d.name_kana)
    |> select([d, office: o], %{
      code: d.code,
      name: d.name,
      name_kana: d.name_kana,
      office_name: o.name,
      employment_type: d.employment_type,
      hired_on: d.hired_on,
      retired_on: d.retired_on,
      license_number: d.license_number,
      license_types: d.license_types,
      license_expires_on: d.license_expires_on,
      note: d.note
    })
  end

  defp query(scope, :operation_reports, params) do
    OperationReport
    |> join(:inner, [r], o in assoc(r, :office), as: :office)
    |> join(:inner, [r], v in assoc(r, :vehicle), as: :vehicle)
    |> join(:inner, [r], d in assoc(r, :driver), as: :driver)
    |> scoped(scope)
    |> filter_office(scope, params["office_id"])
    |> filter_period(:operation_date, params["from"], params["to"])
    |> filter_eq(:vehicle_id, params["vehicle_id"])
    |> filter_eq(:driver_id, params["driver_id"])
    |> filter_eq(:status, params["status"])
    |> order_by([r], desc: r.operation_date, desc: r.departed_at)
    |> select([r, office: o, vehicle: v, driver: d], %{
      operation_date: r.operation_date,
      office_name: o.name,
      plate_number: v.plate_number,
      driver_name: d.name,
      departed_at: r.departed_at,
      returned_at: r.returned_at,
      start_odometer: r.start_odometer,
      end_odometer: r.end_odometer,
      distance_km: r.distance_km,
      destination: r.destination,
      cargo_type: r.cargo_type,
      rest_minutes: r.rest_minutes,
      status: r.status,
      note: r.note
    })
  end

  defp query(scope, :maintenances, params) do
    Maintenance
    |> join(:inner, [m], o in assoc(m, :office), as: :office)
    |> join(:inner, [m], v in assoc(m, :vehicle), as: :vehicle)
    |> scoped(scope)
    |> filter_office(scope, params["office_id"])
    |> filter_period(:performed_on, params["from"], params["to"])
    |> filter_eq(:vehicle_id, params["vehicle_id"])
    |> filter_eq(:category, params["category"])
    |> search_maintenances(params["q"])
    |> order_by([m], desc: m.performed_on, desc: m.inserted_at)
    |> select([m, office: o, vehicle: v], %{
      performed_on: m.performed_on,
      plate_number: v.plate_number,
      office_name: o.name,
      category: m.category,
      odometer: m.odometer,
      vendor: m.vendor,
      cost_yen: m.cost_yen,
      next_scheduled_on: m.next_scheduled_on,
      description: m.description
    })
  end

  defp query(scope, :incidents, params) do
    Incident
    |> join(:inner, [i], o in assoc(i, :office), as: :office)
    |> join(:inner, [i], v in assoc(i, :vehicle), as: :vehicle)
    |> join(:left, [i], d in assoc(i, :driver), as: :driver)
    |> scoped(scope)
    |> filter_office(scope, params["office_id"])
    |> filter_datetime_period(params["from"], params["to"])
    |> filter_eq(:category, params["category"])
    |> filter_eq(:status, params["status"])
    |> filter_eq(:vehicle_id, params["vehicle_id"])
    |> filter_shared(params["shared"])
    |> search([:place, :description], params["q"])
    |> order_by([i], desc: i.occurred_at, desc: i.id)
    |> select([i, office: o, vehicle: v, driver: d], %{
      occurred_at: i.occurred_at,
      office_name: o.name,
      plate_number: v.plate_number,
      driver_name: d.name,
      category: i.category,
      place: i.place,
      weather: i.weather,
      status: i.status,
      shared_company_wide: i.shared_company_wide,
      police_reported: i.police_reported,
      description: i.description,
      counterpart: i.counterpart,
      damage: i.damage,
      direct_cause: i.direct_cause,
      background_factor: i.background_factor,
      countermeasure: i.countermeasure,
      countermeasure_due_on: i.countermeasure_due_on,
      countermeasure_owner: i.countermeasure_owner
    })
  end

  # 出力は拠点単位で完結させる。運行管理者のCSVには他拠点の行を入れない
  # （事故・ヒヤリは全社共有された他拠点の記録も参照できるが、統計と同じく出力対象にしない）。
  defp scoped(query, %Scope{role: :admin}), do: query

  defp scoped(query, %Scope{office_id: office_id}) do
    where(query, [x], x.office_id == ^office_id)
  end

  defp filter_office(query, %Scope{role: :admin}, office_id)
       when is_binary(office_id) and office_id != "" do
    where(query, [x], x.office_id == ^office_id)
  end

  defp filter_office(query, _scope, _office_id), do: query

  defp filter_eq(query, field, value) when is_binary(value) and value != "" do
    where(query, [x], field(x, ^field) == ^value)
  end

  defp filter_eq(query, _field, _value), do: query

  defp filter_vehicle_status(query, "all"), do: query

  defp filter_vehicle_status(query, status) when is_binary(status) and status != "" do
    where(query, [v], v.status == ^status)
  end

  defp filter_vehicle_status(query, _status), do: where(query, [v], v.status != :scrapped)

  defp filter_employment_type(query, "all"), do: query

  defp filter_employment_type(query, employment_type)
       when is_binary(employment_type) and employment_type != "" do
    where(query, [d], d.employment_type == ^employment_type)
  end

  defp filter_employment_type(query, _employment_type) do
    where(query, [d], d.employment_type != :retired)
  end

  defp filter_shared(query, "true"), do: where(query, [i], i.shared_company_wide == true)
  defp filter_shared(query, _shared), do: query

  defp filter_period(query, field, from, to) do
    query
    |> then(&maybe_where_gte(&1, field, parse_date(from)))
    |> then(&maybe_where_lte(&1, field, parse_date(to)))
  end

  defp maybe_where_gte(query, _field, nil), do: query

  defp maybe_where_gte(query, field, value) do
    where(query, [x], field(x, ^field) >= ^value)
  end

  defp maybe_where_lte(query, _field, nil), do: query

  defp maybe_where_lte(query, field, value) do
    where(query, [x], field(x, ^field) <= ^value)
  end

  # 発生日時はUTC保存のため、JSTの日付の範囲に直して突き合わせる
  defp filter_datetime_period(query, from, to) do
    query
    |> then(fn q ->
      case parse_date(from) do
        nil -> q
        date -> where(q, [i], i.occurred_at >= ^beginning_of_day(date))
      end
    end)
    |> then(fn q ->
      case parse_date(to) do
        nil -> q
        date -> where(q, [i], i.occurred_at <= ^end_of_day(date))
      end
    end)
  end

  defp beginning_of_day(date), do: date |> DateTime.new!(~T[00:00:00]) |> DateTime.add(-9, :hour)
  defp end_of_day(date), do: date |> DateTime.new!(~T[23:59:59]) |> DateTime.add(-9, :hour)

  defp search(query, _fields, keyword) when keyword in [nil, ""], do: query

  defp search(query, fields, keyword) do
    pattern = "%#{String.trim(keyword)}%"

    condition =
      Enum.reduce(fields, dynamic(false), fn field, acc ->
        dynamic([x], ^acc or ilike(field(x, ^field), ^pattern))
      end)

    where(query, ^condition)
  end

  defp search_maintenances(query, keyword) when keyword in [nil, ""], do: query

  defp search_maintenances(query, keyword) do
    pattern = "%#{String.trim(keyword)}%"

    where(query, [m, vehicle: v], ilike(v.plate_number, ^pattern) or ilike(m.vendor, ^pattern))
  end

  defp parse_date(value) when is_binary(value) and value != "" do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _error -> nil
    end
  end

  defp parse_date(_value), do: nil
end
