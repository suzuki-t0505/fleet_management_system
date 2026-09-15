defmodule CoreApp.ReportsTest do
  use CoreApp.DataCase, async: true

  import CoreApp.AccountsFixtures
  import CoreApp.DriversFixtures
  import CoreApp.IncidentsFixtures
  import CoreApp.MaintenancesFixtures
  import CoreApp.OfficesFixtures
  import CoreApp.OperationReportsFixtures
  import CoreApp.VehiclesFixtures

  alias CoreApp.Accounts.Scope
  alias CoreApp.OperationReports
  alias CoreApp.Reports
  alias CoreApp.Utils.ConvertDatetime

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

  defp approved_report(scope, vehicle, driver, attrs \\ %{}) do
    report = submitted_report_fixture(scope, vehicle, driver, attrs)
    {:ok, approved} = OperationReports.approve_report(scope, report)

    approved
  end

  describe "distance_report/2" do
    setup :setup_data

    test "承認済みの日報だけを月 × 車両で集計する", ctx do
      %{manager_a: scope, vehicle_a: vehicle, driver_a: driver} = ctx

      approved_report(scope, vehicle, driver, %{
        "start_odometer" => "1000",
        "end_odometer" => "1100"
      })

      # 提出済み（未承認）は集計に入らない
      submitted_report_fixture(scope, vehicle, driver, %{
        "start_odometer" => "2000",
        "end_odometer" => "2500"
      })

      assert [row] = Reports.distance_report(scope).entries
      assert row.key_name == "品川100あ11"
      assert row.distance_km == 100
      assert row.operating_days == 1
      assert row.report_count == 1
      assert row.month == Date.beginning_of_month(ConvertDatetime.today())
    end

    test "集計軸を運転者と拠点に切り替えられる", ctx do
      %{manager_a: scope, vehicle_a: vehicle, driver_a: driver, office_a: office} = ctx
      approved_report(scope, vehicle, driver)

      assert [row] = Reports.distance_report(scope, %{"axis" => "driver"}).entries
      assert row.key_name == driver.name

      assert [row] = Reports.distance_report(scope, %{"axis" => "office"}).entries
      assert row.key_name == office.name
    end

    test "他拠点の実績は混ざらない", ctx do
      %{manager_a: scope_a, manager_b: scope_b} = ctx
      approved_report(scope_a, ctx.vehicle_a, ctx.driver_a)
      approved_report(scope_b, ctx.vehicle_b, ctx.driver_b)

      assert [row] = Reports.distance_report(scope_a).entries
      assert row.key_name == "品川100あ11"

      assert Reports.distance_report(ctx.admin).total_entries == 2
    end

    test "期間外の日報は集計されない", ctx do
      %{manager_a: scope} = ctx
      approved_report(scope, ctx.vehicle_a, ctx.driver_a)

      last_month =
        ConvertDatetime.today()
        |> Date.beginning_of_month()
        |> Date.add(-1)
        |> Date.to_iso8601()
        |> String.slice(0, 7)

      assert Reports.distance_report(scope, %{"from" => last_month, "to" => last_month}).entries ==
               []
    end
  end

  describe "fuel_report/2" do
    setup :setup_data

    test "燃費と給油金額を集計する", ctx do
      %{manager_a: scope, vehicle_a: vehicle, driver_a: driver} = ctx
      today = ConvertDatetime.today()
      departed_at = DateTime.new!(today, ~T[00:00:00]) |> DateTime.add(-9, :hour)

      approved_report(scope, vehicle, driver, %{
        "start_odometer" => "1000",
        "end_odometer" => "1200",
        "refuelings" => %{
          "0" => %{
            "refueled_at" => DateTime.to_iso8601(DateTime.add(departed_at, 1, :hour)),
            "liters" => "40.0",
            "amount_yen" => "6000"
          }
        }
      })

      assert [row] = Reports.fuel_report(scope).entries
      assert row.distance_km == 200
      assert Decimal.equal?(row.liters, Decimal.new("40.00"))
      assert Decimal.equal?(row.km_per_liter, Decimal.new("5.00"))
      assert Decimal.equal?(row.amount_yen, Decimal.new("6000"))
    end

    test "給油が無い場合は燃費が空になる", ctx do
      %{manager_a: scope} = ctx
      approved_report(scope, ctx.vehicle_a, ctx.driver_a)

      assert [row] = Reports.fuel_report(scope).entries
      assert row.km_per_liter == nil
      assert row.liters == nil
    end
  end

  describe "maintenance_cost_report/2" do
    setup :setup_data

    test "区分ごとに費用と件数を集計する", ctx do
      %{manager_a: scope, vehicle_a: vehicle} = ctx
      maintenance_fixture(scope, vehicle, %{"category" => "oil", "cost_yen" => "8000"})
      maintenance_fixture(scope, vehicle, %{"category" => "oil", "cost_yen" => "7000"})
      maintenance_fixture(scope, vehicle, %{"category" => "tire", "cost_yen" => "40000"})

      rows = Reports.maintenance_cost_report(scope).entries
      oil = Enum.find(rows, &(&1.category == :oil))
      tire = Enum.find(rows, &(&1.category == :tire))

      assert oil.cost_yen == 15_000
      assert oil.maintenance_count == 2
      assert tire.cost_yen == 40_000
    end

    test "拠点軸に切り替えられる", ctx do
      %{manager_a: scope, office_a: office} = ctx
      maintenance_fixture(scope, ctx.vehicle_a)

      assert [row] = Reports.maintenance_cost_report(scope, %{"axis" => "office"}).entries
      assert row.key_name == office.name
    end
  end

  describe "incident_report/2" do
    setup :setup_data

    test "件数と完了率を集計する", ctx do
      %{manager_a: scope, office_a: office} = ctx
      reporter = user_fixture(%{office_id: office.id}) |> Scope.for_user()
      approver = manager_fixture(%{office_id: office.id}) |> Scope.for_user()

      incident_fixture(reporter, ctx.vehicle_a)
      closed = countermeasure_reported_fixture(scope, ctx.vehicle_a)
      {:ok, _closed} = CoreApp.Incidents.approve_incident(approver, closed)

      assert [row] = Reports.incident_report(scope).entries
      assert row.key_name == office.name
      assert row.category == :near_miss
      assert row.total_count == 2
      assert row.closed_count == 1
      assert row.completion_rate == 50
    end
  end

  describe "monthly_activity/2 と office_summaries/2" do
    setup :setup_data

    test "当月の稼働台数と走行距離を返す", ctx do
      %{manager_a: scope} = ctx

      approved_report(scope, ctx.vehicle_a, ctx.driver_a, %{
        "start_odometer" => "1000",
        "end_odometer" => "1150"
      })

      assert Reports.monthly_activity(scope) == %{active_vehicles: 1, distance_km: 150}
    end

    test "拠点別の内訳を返す", ctx do
      %{admin: admin, manager_a: scope_a, office_a: office_a} = ctx

      approved_report(scope_a, ctx.vehicle_a, ctx.driver_a, %{
        "start_odometer" => "1000",
        "end_odometer" => "1300"
      })

      submitted_report_fixture(scope_a, ctx.vehicle_a, ctx.driver_a)

      summaries = Reports.office_summaries(admin)
      summary_a = Enum.find(summaries, &(&1.office.id == office_a.id))

      assert summary_a.distance_km == 300
      assert summary_a.submitted_reports == 1
      assert length(summaries) == 2
    end
  end

  describe "all_report_rows/3" do
    setup :setup_data

    test "ページネーションせずに全行を返す", ctx do
      %{manager_a: scope} = ctx
      approved_report(scope, ctx.vehicle_a, ctx.driver_a)

      assert [row] = Reports.all_report_rows(scope, :distance, %{})
      assert row.key_name == "品川100あ11"
    end
  end
end
