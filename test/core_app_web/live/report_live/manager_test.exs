defmodule CoreAppWeb.ReportLive.ManagerTest do
  use CoreAppWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import CoreApp.AccountsFixtures
  import CoreApp.DriversFixtures
  import CoreApp.MaintenancesFixtures
  import CoreApp.OfficesFixtures
  import CoreApp.OperationReportsFixtures
  import CoreApp.VehiclesFixtures

  alias CoreApp.Accounts.Scope
  alias CoreApp.OperationReports

  setup %{conn: conn} do
    office = office_fixture(%{"name" => "A営業所"})
    manager = manager_fixture(%{office_id: office.id})
    scope = Scope.for_user(manager)
    vehicle = vehicle_fixture(scope, %{"plate_number" => "品川100あ11"})
    driver = driver_fixture(scope, %{"name" => "運転 太郎"})

    report =
      submitted_report_fixture(scope, vehicle, driver, %{
        "start_odometer" => "1000",
        "end_odometer" => "1250"
      })

    {:ok, _approved} = OperationReports.approve_report(scope, report)

    %{
      conn: log_in_user(conn, manager),
      scope: scope,
      office: office,
      vehicle: vehicle,
      driver: driver
    }
  end

  test "既定では走行距離集計を表示する", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/management/reports")

    assert html =~ "走行距離集計"
    assert html =~ "品川100あ11"
    assert html =~ "250 km"
    assert html =~ "稼働日数"
  end

  test "集計軸を切り替えられる", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/management/reports")

    html = lv |> form("#search-bar", %{"axis" => "driver"}) |> render_change()

    assert html =~ "運転 太郎"
    refute html =~ "品川100あ11"
  end

  test "集計の種類を切り替えられる", %{conn: conn, scope: scope, vehicle: vehicle} do
    maintenance_fixture(scope, vehicle, %{"category" => "oil", "cost_yen" => "8000"})

    {:ok, lv, _html} = live(conn, ~p"/management/reports")

    html = lv |> form("#search-bar", %{"report" => "maintenance_cost"}) |> render_change()

    assert html =~ "オイル交換"
    assert html =~ "8,000 円"

    html = lv |> form("#search-bar", %{"report" => "fuel"}) |> render_change()
    assert html =~ "燃費"
  end

  test "期間外にすると空状態になる", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/management/reports")

    html = lv |> form("#search-bar", %{"from" => "2020-01", "to" => "2020-02"}) |> render_change()

    assert html =~ "集計対象のデータがありません"
  end

  test "CSV出力のリンクに絞り込み条件が引き継がれる", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/management/reports?#{%{"report" => "fuel"}}")

    assert html =~ "/management/exports/reports/fuel"
  end

  test "一般利用者は参照できない", %{conn: conn, office: office} do
    member = user_fixture(%{office_id: office.id})

    assert {:error, {:redirect, %{to: "/", flash: flash}}} =
             conn |> log_in_user(member) |> live(~p"/management/reports")

    assert flash["error"] == "このページを表示する権限がありません"
  end
end
