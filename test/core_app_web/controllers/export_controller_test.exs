defmodule CoreAppWeb.ExportControllerTest do
  use CoreAppWeb.ConnCase, async: true

  import CoreApp.AccountsFixtures
  import CoreApp.DriversFixtures
  import CoreApp.OfficesFixtures
  import CoreApp.OperationReportsFixtures
  import CoreApp.VehiclesFixtures

  alias CoreApp.Accounts.Scope
  alias CoreApp.OperationReports

  setup %{conn: conn} do
    office = office_fixture(%{"name" => "A営業所"})
    other_office = office_fixture(%{"name" => "B営業所"})

    manager = manager_fixture(%{office_id: office.id})
    scope = Scope.for_user(manager)

    %{
      conn: log_in_user(conn, manager),
      manager: manager,
      scope: scope,
      office: office,
      other_office: other_office,
      vehicle: vehicle_fixture(scope, %{"plate_number" => "品川100あ11"}),
      driver: driver_fixture(scope, %{"name" => "運転 太郎"})
    }
  end

  test "車両のCSVをBOM付き・CRLFで出力する", %{conn: conn} do
    conn = get(conn, ~p"/management/exports/vehicles")

    body = response(conn, 200)

    assert get_resp_header(conn, "content-type") == ["text/csv; charset=utf-8"]
    assert String.starts_with?(body, "﻿車両番号,")
    assert body =~ "\r\n"
    assert body =~ "品川100あ11"
    assert body =~ "A営業所"

    assert [disposition] = get_resp_header(conn, "content-disposition")
    assert disposition =~ "attachment; filename*=UTF-8''"
    assert disposition =~ URI.encode("車両一覧")
  end

  test "画面の絞り込み条件が反映される", %{conn: conn, scope: scope} do
    vehicle_fixture(scope, %{"plate_number" => "練馬500さ22"})

    body = conn |> get(~p"/management/exports/vehicles?#{%{"q" => "練馬"}}") |> response(200)

    assert body =~ "練馬500さ22"
    refute body =~ "品川100あ11"
  end

  test "他拠点の行は出力されない", %{conn: conn, other_office: other_office} do
    other = manager_fixture(%{office_id: other_office.id}) |> Scope.for_user()
    vehicle_fixture(other, %{"plate_number" => "他拠点あ99"})

    body = conn |> get(~p"/management/exports/vehicles") |> response(200)

    refute body =~ "他拠点あ99"
  end

  test "運行日報のCSVを出力する", %{conn: conn, scope: scope, vehicle: vehicle, driver: driver} do
    report = submitted_report_fixture(scope, vehicle, driver)
    {:ok, _approved} = OperationReports.approve_report(scope, report)

    body = conn |> get(~p"/management/exports/operation_reports") |> response(200)

    assert body =~ "運行日,拠点,車両番号"
    assert body =~ "運転 太郎"
    assert body =~ "承認済み"
  end

  test "集計レポートのCSVを出力する", %{conn: conn, scope: scope, vehicle: vehicle, driver: driver} do
    report = submitted_report_fixture(scope, vehicle, driver)
    {:ok, _approved} = OperationReports.approve_report(scope, report)

    body = conn |> get(~p"/management/exports/reports/distance") |> response(200)

    assert String.starts_with?(body, "﻿月,対象,走行距離(km)")
    assert body =~ "品川100あ11"
  end

  test "上限を超える場合は出力せず、絞り込みを促す", %{conn: conn, scope: scope} do
    vehicle_fixture(scope, %{"plate_number" => "練馬500さ22"})

    Application.put_env(:core_app, :csv_max_rows, 1)
    on_exit(fn -> Application.delete_env(:core_app, :csv_max_rows) end)

    conn = get(conn, ~p"/management/exports/vehicles")

    assert redirected_to(conn) == ~p"/management/vehicles"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "絞り込んでください"
  end

  test "知らないリソースは404を返す", %{conn: conn} do
    assert conn |> get(~p"/management/exports/unknown") |> response(404)
    assert conn |> get(~p"/management/exports/reports/unknown") |> response(404)
  end

  test "一般利用者は出力できない", %{conn: conn, office: office} do
    member = user_fixture(%{office_id: office.id})

    conn = conn |> log_in_user(member) |> get(~p"/management/exports/vehicles")

    assert redirected_to(conn) == ~p"/"
  end

  test "未ログインの利用者はログイン画面へ送られる" do
    conn = get(build_conn(), ~p"/management/exports/vehicles")

    assert redirected_to(conn) == ~p"/users/log-in"
  end
end
