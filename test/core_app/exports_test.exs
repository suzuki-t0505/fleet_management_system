defmodule CoreApp.ExportsTest do
  use CoreApp.DataCase, async: true

  import CoreApp.AccountsFixtures
  import CoreApp.DriversFixtures
  import CoreApp.IncidentsFixtures
  import CoreApp.MaintenancesFixtures
  import CoreApp.OfficesFixtures
  import CoreApp.OperationReportsFixtures
  import CoreApp.VehiclesFixtures

  alias CoreApp.Accounts.Scope
  alias CoreApp.Exports

  defp setup_data(_context) do
    office_a = office_fixture(%{"name" => "A営業所"})
    office_b = office_fixture(%{"name" => "B営業所"})

    manager_a = manager_fixture(%{office_id: office_a.id}) |> Scope.for_user()
    manager_b = manager_fixture(%{office_id: office_b.id}) |> Scope.for_user()
    admin = admin_fixture(%{office_id: office_a.id}) |> Scope.for_user()

    %{
      office_a: office_a,
      office_b: office_b,
      manager_a: manager_a,
      manager_b: manager_b,
      admin: admin,
      vehicle_a: vehicle_fixture(manager_a, %{"plate_number" => "品川100あ11"}),
      vehicle_b: vehicle_fixture(manager_b, %{"plate_number" => "練馬500さ22"}),
      driver_a: driver_fixture(manager_a, %{"name" => "運転 太郎"}),
      driver_b: driver_fixture(manager_b)
    }
  end

  defp rows(scope, resource, params \\ %{}) do
    {:ok, rows} = Exports.stream_rows(scope, resource, params, &Enum.to_list/1)

    rows
  end

  describe "車両" do
    setup :setup_data

    test "自拠点の車両だけを出力する", ctx do
      assert [row] = rows(ctx.manager_a, :vehicles)
      assert row.plate_number == "品川100あ11"
      assert row.office_name == "A営業所"

      assert Exports.count(ctx.admin, :vehicles) == 2
    end

    test "一覧と同じ条件で絞り込める", ctx do
      vehicle_fixture(ctx.manager_a, %{"plate_number" => "廃車予定", "status" => "scrapped"})

      assert length(rows(ctx.manager_a, :vehicles)) == 1
      assert length(rows(ctx.manager_a, :vehicles, %{"status" => "all"})) == 2
      assert [row] = rows(ctx.manager_a, :vehicles, %{"q" => "品川"})
      assert row.plate_number == "品川100あ11"
    end
  end

  describe "運転者" do
    setup :setup_data

    test "退職者は既定で出力しない", ctx do
      driver_fixture(ctx.manager_a, %{
        "name" => "退職 次郎",
        "employment_type" => "retired",
        "retired_on" => "2026-08-31"
      })

      assert [row] = rows(ctx.manager_a, :drivers)
      assert row.name == "運転 太郎"
      assert length(rows(ctx.manager_a, :drivers, %{"employment_type" => "all"})) == 2
    end
  end

  describe "運行日報" do
    setup :setup_data

    test "期間とステータスで絞り込める", ctx do
      report = report_fixture(ctx.manager_a, ctx.vehicle_a, ctx.driver_a)

      assert [row] = rows(ctx.manager_a, :operation_reports)
      assert row.plate_number == "品川100あ11"
      assert row.driver_name == "運転 太郎"
      assert row.status == :draft

      assert rows(ctx.manager_a, :operation_reports, %{"status" => "approved"}) == []

      tomorrow = Date.add(report.operation_date, 1) |> Date.to_iso8601()
      assert rows(ctx.manager_a, :operation_reports, %{"from" => tomorrow}) == []
    end
  end

  describe "点検整備" do
    setup :setup_data

    test "車両と区分で絞り込める", ctx do
      maintenance_fixture(ctx.manager_a, ctx.vehicle_a, %{"vendor" => "テスト工場"})

      assert [row] = rows(ctx.manager_a, :maintenances)
      assert row.vendor == "テスト工場"
      assert row.plate_number == "品川100あ11"

      assert rows(ctx.manager_a, :maintenances, %{"category" => "inspection"}) == []
      assert length(rows(ctx.manager_a, :maintenances, %{"q" => "テスト"})) == 1
    end
  end

  describe "事故・ヒヤリ" do
    setup :setup_data

    test "他拠点の全社共有された記録は出力しない", ctx do
      incident_fixture(ctx.manager_a, ctx.vehicle_a, %{"place" => "自拠点の場所"})
      shared = incident_fixture(ctx.manager_b, ctx.vehicle_b, %{"place" => "他拠点の場所"})
      {:ok, _shared} = CoreApp.Incidents.share_incident(ctx.admin, shared, true)

      places = ctx.manager_a |> rows(:incidents) |> Enum.map(& &1.place)

      assert places == ["自拠点の場所"]
    end

    test "区分で絞り込める", ctx do
      incident_fixture(ctx.manager_a, ctx.vehicle_a)
      incident_fixture(ctx.manager_a, ctx.vehicle_a, %{"category" => "injury"})

      assert length(rows(ctx.manager_a, :incidents, %{"category" => "injury"})) == 1
    end
  end

  describe "count/3" do
    setup :setup_data

    test "出力対象の行数を返す", ctx do
      assert Exports.count(ctx.manager_a, :vehicles) == 1
      assert Exports.count(ctx.manager_b, :vehicles) == 1
      assert Exports.count(ctx.admin, :vehicles) == 2
    end
  end
end
