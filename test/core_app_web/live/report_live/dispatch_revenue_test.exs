defmodule CoreAppWeb.ReportLive.DispatchRevenueTest do
  use CoreAppWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import CoreApp.AccountsFixtures
  import CoreApp.DispatchesFixtures
  import CoreApp.OfficesFixtures
  import CoreApp.ShippersFixtures

  alias CoreApp.Accounts.Scope

  setup %{conn: conn} do
    office = office_fixture(%{"name" => "A営業所"})
    manager = manager_fixture(%{office_id: office.id})
    scope = Scope.for_user(manager)
    shipper = shipper_fixture(scope, %{"name" => "北海道物流"})

    dispatch_fixture(scope, %{
      "shipper_id" => shipper.id,
      "course_fare_yen" => "30000",
      "toll_yen" => "1500"
    })

    %{conn: log_in_user(conn, manager)}
  end

  test "配車売上集計を荷主別に表示する", %{conn: conn} do
    params = %{"report" => "dispatch_revenue", "from" => "2026-10", "to" => "2026-10"}

    {:ok, _lv, html} = live(conn, ~p"/management/reports?#{params}")

    assert html =~ "配車売上集計"
    assert html =~ "北海道物流"
    assert html =~ "30,000 円"
    assert html =~ "1,500 円"
    assert html =~ "31,500 円"
  end

  test "集計軸を切り替えられる", %{conn: conn} do
    params = %{
      "report" => "dispatch_revenue",
      "axis" => "office",
      "from" => "2026-10",
      "to" => "2026-10"
    }

    {:ok, _lv, html} = live(conn, ~p"/management/reports?#{params}")

    assert html =~ "A営業所"
    refute html =~ "北海道物流"
  end

  test "集計対象が無い月は空状態を表示する", %{conn: conn} do
    params = %{"report" => "dispatch_revenue", "from" => "2020-01", "to" => "2020-01"}

    {:ok, _lv, html} = live(conn, ~p"/management/reports?#{params}")

    assert html =~ "集計対象のデータがありません"
  end
end
