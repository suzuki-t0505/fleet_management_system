defmodule CoreAppWeb.ExportColumns do
  @moduledoc """
  CSVの列定義です。ヘッダー（日本語）と、1行分の値の並びを決めます。

  列挙値の日本語化は各画面の `Labels` と同じものを使い、画面とCSVで表記がずれないようにします。
  """

  alias CoreAppWeb.DriverLive.Labels, as: DriverLabels
  alias CoreAppWeb.IncidentLive.Labels, as: IncidentLabels
  alias CoreAppWeb.MaintenanceLive.Labels, as: MaintenanceLabels
  alias CoreAppWeb.OperationReportLive.Labels, as: ReportLabels
  alias CoreAppWeb.StatusComponents
  alias CoreAppWeb.VehicleLive.Labels, as: VehicleLabels

  @headers %{
    vehicles: [
      "車両番号",
      "車台番号",
      "車種区分",
      "メーカー",
      "車名",
      "初度登録年月",
      "ステータス",
      "拠点",
      "車検満了日",
      "自賠責保険満了日",
      "任意保険満了日",
      "次回3ヶ月点検",
      "次回12ヶ月点検",
      "最終オドメーター",
      "備考"
    ],
    drivers: [
      "運転者コード",
      "氏名",
      "氏名かな",
      "拠点",
      "雇用区分",
      "入社年月日",
      "退職年月日",
      "免許証番号",
      "免許種類",
      "免許証有効期限",
      "備考"
    ],
    operation_reports: [
      "運行日",
      "拠点",
      "車両番号",
      "運転者",
      "出発日時",
      "帰着日時",
      "出発時オドメーター",
      "帰着時オドメーター",
      "走行距離(km)",
      "主な行き先",
      "荷種",
      "休憩時間(分)",
      "ステータス",
      "備考"
    ],
    maintenances: [
      "実施日",
      "車両番号",
      "拠点",
      "区分",
      "オドメーター",
      "実施業者",
      "費用(円)",
      "次回予定日",
      "作業内容"
    ],
    incidents: [
      "発生日時",
      "拠点",
      "車両番号",
      "運転者",
      "区分",
      "発生場所",
      "天候",
      "ステータス",
      "全社共有",
      "警察への届出",
      "発生状況",
      "相手方の概要",
      "被害・損害の概要",
      "直接原因",
      "背景要因",
      "対策内容",
      "対策実施予定日",
      "実施責任者"
    ]
  }

  @report_headers %{
    distance: ["月", "対象", "走行距離(km)", "稼働日数", "日報件数"],
    fuel: ["月", "車両番号", "走行距離(km)", "給油量(L)", "燃費(km/L)", "給油金額(円)"],
    maintenance_cost: ["月", "対象", "区分", "費用(円)", "件数"],
    incident: ["月", "拠点", "区分", "発生件数", "改善報告完了", "完了率(%)"]
  }

  @report_filenames %{
    distance: "走行距離集計",
    fuel: "燃費集計",
    maintenance_cost: "整備費集計",
    incident: "事故ヒヤリ集計"
  }

  @filenames %{
    vehicles: "車両一覧",
    drivers: "運転者一覧",
    operation_reports: "運行日報",
    maintenances: "点検整備記録",
    incidents: "事故ヒヤリ記録"
  }

  @doc """
  ヘッダー行を返します。
  """
  def headers(resource), do: Map.fetch!(@headers, resource)

  @doc """
  集計レポートのヘッダー行を返します。
  """
  def report_headers(report), do: Map.fetch!(@report_headers, report)

  @doc """
  集計レポートのファイル名に使う日本語の名前を返します。
  """
  def report_filename_base(report), do: Map.fetch!(@report_filenames, report)

  @doc """
  集計レポート1行分の値を、ヘッダーと同じ並びで返します。
  """
  def report_values(:distance, row) do
    [month(row.month), row.key_name, row.distance_km, row.operating_days, row.report_count]
  end

  def report_values(:fuel, row) do
    [
      month(row.month),
      row.key_name,
      row.distance_km,
      row.liters,
      row.km_per_liter,
      row.amount_yen
    ]
  end

  def report_values(:maintenance_cost, row) do
    [
      month(row.month),
      row.key_name,
      MaintenanceLabels.category(row.category),
      row.cost_yen,
      row.maintenance_count
    ]
  end

  def report_values(:incident, row) do
    [
      month(row.month),
      row.key_name,
      IncidentLabels.category(row.category),
      row.total_count,
      row.closed_count,
      row.completion_rate
    ]
  end

  @doc """
  集計の月を `YYYY/MM` 形式で返します。
  """
  def month(nil), do: "-"

  def month(%Date{} = date) do
    "#{date.year}/#{String.pad_leading(to_string(date.month), 2, "0")}"
  end

  @doc """
  ファイル名に使う日本語のリソース名を返します。
  """
  def filename_base(resource), do: Map.fetch!(@filenames, resource)

  @doc """
  1行分の値を、ヘッダーと同じ並びで返します。
  """
  def values(:vehicles, row) do
    [
      row.plate_number,
      row.vin,
      VehicleLabels.vehicle_class(row.vehicle_class),
      row.maker,
      row.model_name,
      row.first_registered_on,
      VehicleLabels.status(row.status),
      row.office_name,
      row.inspection_expires_on,
      row.liability_insurance_expires_on,
      row.voluntary_insurance_expires_on,
      row.next_periodic_3m_on,
      row.next_periodic_12m_on,
      row.latest_odometer,
      row.note
    ]
  end

  def values(:drivers, row) do
    [
      row.code,
      row.name,
      row.name_kana,
      row.office_name,
      DriverLabels.employment_type(row.employment_type),
      row.hired_on,
      row.retired_on,
      row.license_number,
      DriverLabels.license_types(row.license_types),
      row.license_expires_on,
      row.note
    ]
  end

  def values(:operation_reports, row) do
    [
      row.operation_date,
      row.office_name,
      row.plate_number,
      row.driver_name,
      StatusComponents.format_datetime(row.departed_at),
      StatusComponents.format_datetime(row.returned_at),
      row.start_odometer,
      row.end_odometer,
      row.distance_km,
      row.destination,
      row.cargo_type,
      row.rest_minutes,
      ReportLabels.status(row.status),
      row.note
    ]
  end

  def values(:maintenances, row) do
    [
      row.performed_on,
      row.plate_number,
      row.office_name,
      MaintenanceLabels.category(row.category),
      row.odometer,
      row.vendor,
      row.cost_yen,
      row.next_scheduled_on,
      row.description
    ]
  end

  def values(:incidents, row) do
    [
      StatusComponents.format_datetime(row.occurred_at),
      row.office_name,
      row.plate_number,
      row.driver_name,
      IncidentLabels.category(row.category),
      row.place,
      IncidentLabels.weather(row.weather),
      IncidentLabels.status(row.status),
      row.shared_company_wide,
      row.police_reported,
      row.description,
      row.counterpart,
      row.damage,
      row.direct_cause,
      row.background_factor,
      row.countermeasure,
      row.countermeasure_due_on,
      row.countermeasure_owner
    ]
  end
end
