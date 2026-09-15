defmodule CoreAppWeb.ExportController do
  @moduledoc """
  一覧のCSVをダウンロードするコントローラです。

  画面の絞り込み条件（クエリパラメータ）をそのまま受け取り、同じ条件の行を出力します。
  全件をメモリに載せないよう、チャンク転送で1行ずつ書き出します。
  """
  use CoreAppWeb, :controller

  alias CoreApp.Exports
  alias CoreApp.Reports
  alias CoreApp.Utils.ConvertDatetime
  alias CoreApp.Utils.Csv
  alias CoreAppWeb.ExportColumns

  @list_paths %{
    vehicles: "/management/vehicles",
    drivers: "/management/drivers",
    operation_reports: "/management/operation_reports",
    maintenances: "/management/maintenances",
    incidents: "/management/incidents"
  }

  def download(conn, %{"resource" => resource} = params) do
    case fetch_resource(resource) do
      nil -> send_resp(conn, 404, "")
      resource -> export(conn, resource, params)
    end
  end

  defp export(conn, resource, params) do
    scope = conn.assigns.current_scope

    if Exports.count(scope, resource, params) > Exports.max_rows() do
      conn
      |> put_flash(
        :error,
        "出力できるのは#{Exports.max_rows()}件までです。期間や条件で絞り込んでください。"
      )
      |> redirect(to: Map.fetch!(@list_paths, resource))
    else
      send_csv(conn, scope, resource, params)
    end
  end

  def download_report(conn, %{"report" => report} = params) do
    case fetch_report(report) do
      nil -> send_resp(conn, 404, "")
      report -> send_report_csv(conn, report, params)
    end
  end

  # 集計後の行数は月数 × 対象数に収まるため、上限の判定は行わない
  defp send_report_csv(conn, report, params) do
    scope = conn.assigns.current_scope

    conn =
      conn
      |> csv_headers(ExportColumns.report_filename_base(report))
      |> chunk!([Csv.bom(), Csv.dump_row(ExportColumns.report_headers(report))])

    scope
    |> Reports.all_report_rows(report, params)
    |> Enum.reduce(conn, fn row, acc ->
      chunk!(acc, Csv.dump_row(ExportColumns.report_values(report, row)))
    end)
  end

  defp send_csv(conn, scope, resource, params) do
    conn =
      conn
      |> csv_headers(ExportColumns.filename_base(resource))
      |> chunk!([Csv.bom(), Csv.dump_row(ExportColumns.headers(resource))])

    {:ok, conn} =
      Exports.stream_rows(scope, resource, params, fn rows ->
        Enum.reduce(rows, conn, fn row, acc ->
          chunk!(acc, Csv.dump_row(ExportColumns.values(resource, row)))
        end)
      end)

    conn
  end

  defp chunk!(conn, iodata) do
    {:ok, conn} = chunk(conn, iodata)

    conn
  end

  defp csv_headers(conn, filename_base) do
    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", content_disposition(filename_base))
    |> put_resp_header("cache-control", "private, no-store")
    |> send_chunked(200)
  end

  # 日本語のファイル名を扱うため RFC 5987 形式で指定する
  defp content_disposition(filename_base) do
    date = ConvertDatetime.today() |> Date.to_iso8601() |> String.replace("-", "")
    filename = "#{filename_base}_#{date}.csv"

    "attachment; filename*=UTF-8''#{URI.encode(filename)}"
  end

  defp fetch_resource(resource) do
    Enum.find(Exports.resources(), &(to_string(&1) == resource))
  end

  defp fetch_report(report) do
    Enum.find(Reports.report_types(), &(to_string(&1) == report))
  end
end
