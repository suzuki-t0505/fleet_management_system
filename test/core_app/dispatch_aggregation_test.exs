defmodule CoreApp.DispatchAggregationTest do
  @moduledoc "配車のCSV出力（Exports）と売上集計（Reports）のテストです。"
  use CoreApp.DataCase, async: true

  import CoreApp.AccountsFixtures
  import CoreApp.DispatchesFixtures
  import CoreApp.DriversFixtures
  import CoreApp.OfficesFixtures
  import CoreApp.ShippersFixtures

  alias CoreApp.Accounts.Scope
  alias CoreApp.Exports
  alias CoreApp.Reports

  @period %{"from" => "2026-10", "to" => "2026-10"}

  defp setup_data(_context) do
    office_a = office_fixture(%{"name" => "A営業所"})
    office_b = office_fixture(%{"name" => "B営業所"})

    manager_a = manager_fixture(%{office_id: office_a.id}) |> Scope.for_user()
    manager_b = manager_fixture(%{office_id: office_b.id}) |> Scope.for_user()
    admin = admin_fixture(%{office_id: office_a.id}) |> Scope.for_user()

    %{
      office_a: office_a,
      manager_a: manager_a,
      manager_b: manager_b,
      admin: admin,
      shipper_a: shipper_fixture(manager_a, %{"name" => "北海道物流"}),
      shipper_b: shipper_fixture(manager_a, %{"name" => "九州運輸"}),
      driver_a: driver_fixture(manager_a, %{"name" => "運転 太郎"})
    }
  end

  defp per_delivery(fares) do
    fares
    |> Enum.with_index()
    |> Map.new(fn {{destination, fare}, index} ->
      {to_string(index), %{"destination" => destination, "fare_yen" => fare}}
    end)
  end

  defp rows(scope, params \\ %{}) do
    {:ok, rows} = Exports.stream_rows(scope, :dispatches, params, &Enum.to_list/1)

    rows
  end

  describe "Exports（配車）" do
    setup :setup_data

    test "自拠点の配車だけを平坦な行で出力する", ctx do
      dispatch_fixture(ctx.manager_a, %{"title" => "自拠点便"})
      dispatch_fixture(ctx.manager_b, %{"title" => "他拠点便"})

      assert [row] = rows(ctx.manager_a)
      assert row.title == "自拠点便"
      assert row.office_name == "A営業所"
      assert Exports.count(ctx.admin, :dispatches) == 2
    end

    test "配送先は順番どおりに連結され、配送ごとは配送料金の合計を出す", ctx do
      dispatch_fixture(ctx.manager_a, %{
        "pricing_type" => "per_delivery",
        "deliveries" => per_delivery([{"東京", "10000"}, {"横浜", "8000"}])
      })

      assert [row] = rows(ctx.manager_a)
      assert row.destinations == "東京、横浜"
      assert row.deliveries_fare_total_yen == 18_000
    end

    test "配送明細が無い配車も出力される", ctx do
      dispatch_fixture(ctx.manager_a)

      assert [row] = rows(ctx.manager_a)
      assert row.destinations == nil
      assert row.deliveries_fare_total_yen == nil
    end

    test "一覧と同じ条件で絞り込める", ctx do
      target =
        dispatch_fixture(ctx.manager_a, %{
          "title" => "朝便",
          "shipper_id" => ctx.shipper_a.id,
          "driver_id" => ctx.driver_a.id,
          "started_at" => "2026-09-30T15:30:00Z",
          "ended_at" => "2026-09-30T18:00:00Z"
        })

      dispatch_fixture(ctx.manager_a, %{
        "title" => "夜便",
        "shipper_id" => ctx.shipper_b.id,
        "started_at" => "2026-10-05T09:00:00Z",
        "ended_at" => "2026-10-05T12:00:00Z"
      })

      titles = fn params -> params |> then(&rows(ctx.manager_a, &1)) |> Enum.map(& &1.title) end

      assert titles.(%{"shipper_id" => ctx.shipper_a.id}) == ["朝便"]
      assert titles.(%{"driver_id" => target.driver_id}) == ["朝便"]
      assert titles.(%{"q" => "朝便"}) == ["朝便"]
      assert titles.(%{"q" => "九州"}) == ["夜便"]
      # 2026-09-30 15:30 UTC は JST で 10/1 00:30
      assert titles.(%{"from" => "2026-10-01", "to" => "2026-10-01"}) == ["朝便"]
    end

    test "配送先でキーワード検索できる", ctx do
      dispatch_fixture(ctx.manager_a, %{
        "title" => "福岡便",
        "deliveries" => per_delivery([{"福岡センター", ""}])
      })

      dispatch_fixture(ctx.manager_a, %{"title" => "他の便"})

      assert [%{title: "福岡便"}] = rows(ctx.manager_a, %{"q" => "福岡"})
    end
  end

  describe "Reports.dispatch_revenue_report/2" do
    setup :setup_data

    test "荷主別に運賃と高速料金を合計する", ctx do
      dispatch_fixture(ctx.manager_a, %{
        "shipper_id" => ctx.shipper_a.id,
        "course_fare_yen" => "30000",
        "toll_yen" => "1500"
      })

      dispatch_fixture(ctx.manager_a, %{
        "shipper_id" => ctx.shipper_a.id,
        "pricing_type" => "per_delivery",
        "toll_yen" => "500",
        "deliveries" => per_delivery([{"東京", "10000"}, {"横浜", "8000"}])
      })

      dispatch_fixture(ctx.manager_a, %{
        "shipper_id" => ctx.shipper_b.id,
        "course_fare_yen" => "5000",
        "toll_yen" => "0"
      })

      %{entries: entries} = Reports.dispatch_revenue_report(ctx.manager_a, @period)

      assert [first, second] = Enum.sort_by(entries, & &1.key_name, :desc)
      assert first.key_name == "北海道物流"
      assert first.dispatch_count == 2
      assert first.fare_yen == 48_000
      assert first.toll_yen == 2_000
      assert first.total_yen == 50_000
      assert first.month == ~D[2026-10-01]

      assert second.key_name == "九州運輸"
      assert second.total_yen == 5_000
    end

    test "コース一括でも配送明細の料金は集計しない", ctx do
      dispatch_fixture(ctx.manager_a, %{
        "course_fare_yen" => "30000",
        "toll_yen" => "0",
        "deliveries" => per_delivery([{"東京", "9999"}])
      })

      assert %{entries: [row]} = Reports.dispatch_revenue_report(ctx.manager_a, @period)
      assert row.fare_yen == 30_000
    end

    test "車両・運転者・拠点の軸で集計できる", ctx do
      dispatch =
        dispatch_fixture(ctx.manager_a, %{
          "driver_id" => ctx.driver_a.id,
          "course_fare_yen" => "10000",
          "toll_yen" => "1000"
        })

      for {axis, expected_name} <- [
            {"vehicle",
             CoreApp.Vehicles.get_vehicle!(ctx.manager_a, dispatch.vehicle_id).plate_number},
            {"driver", "運転 太郎"},
            {"office", "A営業所"}
          ] do
        params = Map.put(@period, "axis", axis)

        assert %{entries: [row]} = Reports.dispatch_revenue_report(ctx.manager_a, params)
        assert row.key_name == expected_name
        assert row.total_yen == 11_000
      end
    end

    test "月はJSTの配送開始日で切る", ctx do
      # 2026-09-30 15:30 UTC = 2026-10-01 00:30 JST（10月）
      dispatch_fixture(ctx.manager_a, %{
        "started_at" => "2026-09-30T15:30:00Z",
        "ended_at" => "2026-09-30T18:00:00Z"
      })

      # 2026-10-31 15:30 UTC = 2026-11-01 00:30 JST（11月）
      dispatch_fixture(ctx.manager_a, %{
        "started_at" => "2026-10-31T15:30:00Z",
        "ended_at" => "2026-10-31T18:00:00Z"
      })

      assert %{entries: [%{month: ~D[2026-10-01], dispatch_count: 1}]} =
               Reports.dispatch_revenue_report(ctx.manager_a, @period)

      assert %{entries: [%{month: ~D[2026-11-01], dispatch_count: 1}]} =
               Reports.dispatch_revenue_report(ctx.manager_a, %{
                 "from" => "2026-11",
                 "to" => "2026-11"
               })
    end

    test "運行管理者には自拠点の売上だけ、管理者は拠点で絞り込める", ctx do
      dispatch_fixture(ctx.manager_a, %{"course_fare_yen" => "10000", "toll_yen" => "0"})
      dispatch_fixture(ctx.manager_b, %{"course_fare_yen" => "20000", "toll_yen" => "0"})

      assert %{entries: [%{total_yen: 10_000}]} =
               Reports.dispatch_revenue_report(ctx.manager_a, @period)

      axis_params = Map.put(@period, "axis", "office")
      assert %{entries: entries} = Reports.dispatch_revenue_report(ctx.admin, axis_params)
      assert entries |> Enum.map(& &1.total_yen) |> Enum.sort() == [10_000, 20_000]

      filtered = Map.put(axis_params, "office_id", ctx.office_a.id)

      assert %{entries: [%{total_yen: 10_000}]} =
               Reports.dispatch_revenue_report(ctx.admin, filtered)
    end

    test "CSV出力用に全行を返す", ctx do
      dispatch_fixture(ctx.manager_a, %{"course_fare_yen" => "10000", "toll_yen" => "500"})

      assert [%{total_yen: 10_500}] =
               Reports.all_report_rows(ctx.manager_a, :dispatch_revenue, @period)
    end
  end
end
