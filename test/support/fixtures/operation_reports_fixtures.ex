defmodule CoreApp.OperationReportsFixtures do
  @moduledoc """
  運行日報のテストデータを生成します。
  """

  alias CoreApp.Accounts.Scope
  alias CoreApp.OperationReports
  alias CoreApp.Utils.ConvertDatetime

  @doc """
  日報の入力値を返します。`vehicle` と `driver` は呼び出し側で渡します。
  """
  def valid_report_attributes(vehicle, driver, attrs \\ %{}) do
    today = ConvertDatetime.today()
    departed_at = DateTime.new!(today, ~T[00:00:00]) |> DateTime.add(-9, :hour)

    Enum.into(attrs, %{
      "vehicle_id" => vehicle.id,
      "driver_id" => driver.id,
      "operation_date" => Date.to_iso8601(today),
      "departed_at" => DateTime.to_iso8601(departed_at),
      "returned_at" => DateTime.to_iso8601(DateTime.add(departed_at, 8, :hour)),
      "start_odometer" => "10000",
      "end_odometer" => "10120",
      "destination" => "東京都港区",
      "cargo_type" => "一般貨物"
    })
  end

  def report_fixture(%Scope{} = scope, vehicle, driver, attrs \\ %{}) do
    {:ok, report} =
      OperationReports.create_operation_report(
        scope,
        valid_report_attributes(vehicle, driver, attrs)
      )

    report
  end

  @doc """
  提出済みの日報を作成します。
  """
  def submitted_report_fixture(%Scope{} = scope, vehicle, driver, attrs \\ %{}) do
    report = report_fixture(scope, vehicle, driver, attrs)
    {:ok, report} = OperationReports.submit_report(scope, report)

    report
  end
end
