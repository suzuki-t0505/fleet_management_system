defmodule CoreAppWeb.AlertLive.ManagerTest do
  use CoreAppWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import CoreApp.AccountsFixtures
  import CoreApp.DriversFixtures
  import CoreApp.OfficesFixtures
  import CoreApp.VehiclesFixtures

  alias CoreApp.Accounts.Scope
  alias CoreApp.Utils.ConvertDatetime

  setup %{conn: conn} do
    office_a = office_fixture(%{"name" => "A営業所"})
    office_b = office_fixture(%{"name" => "B営業所"})

    manager = manager_fixture(%{office_id: office_a.id})

    %{
      conn: log_in_user(conn, manager),
      scope: Scope.for_user(manager),
      other_scope: Scope.for_user(manager_fixture(%{office_id: office_b.id})),
      admin: admin_fixture(%{office_id: office_a.id}),
      today: ConvertDatetime.today()
    }
  end

  defp in_days(today, days), do: today |> Date.add(days) |> Date.to_iso8601()

  test "自拠点の期限が残日数の昇順で表示される", %{conn: conn, scope: scope, today: today} do
    vehicle_fixture(scope, %{
      "plate_number" => "品川100あ40",
      "inspection_expires_on" => in_days(today, 40)
    })

    vehicle_fixture(scope, %{
      "plate_number" => "品川100あ01",
      "inspection_expires_on" => in_days(today, -1)
    })

    {:ok, _lv, html} = live(conn, ~p"/management/alerts")

    assert html =~ "品川100あ01"
    assert html =~ "品川100あ40"
    assert html =~ "超過 1日"

    overdue_at = :binary.match(html, "品川100あ01") |> elem(0)
    soon_at = :binary.match(html, "品川100あ40") |> elem(0)
    assert overdue_at < soon_at
  end

  test "他拠点の期限は表示されない", %{conn: conn, other_scope: other_scope, today: today} do
    vehicle_fixture(other_scope, %{
      "plate_number" => "練馬500さ99",
      "inspection_expires_on" => in_days(today, 3)
    })

    {:ok, _lv, html} = live(conn, ~p"/management/alerts")

    refute html =~ "練馬500さ99"
    assert html =~ "条件に一致する期限がありません"
  end

  test "期限種別と残日数で絞り込める", %{conn: conn, scope: scope, today: today} do
    vehicle_fixture(scope, %{
      "plate_number" => "品川100あ11",
      "inspection_expires_on" => in_days(today, 50)
    })

    driver_fixture(scope, %{"name" => "免許 太郎", "license_expires_on" => in_days(today, -3)})

    {:ok, lv, _html} = live(conn, ~p"/management/alerts")

    html = lv |> form("#search-bar", %{"alert_type" => "license"}) |> render_change()

    assert html =~ "免許 太郎"
    refute html =~ "品川100あ11"

    html =
      lv |> form("#search-bar", %{"alert_type" => "", "within" => "overdue"}) |> render_change()

    assert html =~ "免許 太郎"
    refute html =~ "品川100あ11"
  end

  test "ダッシュボードから件数で遷移できる", %{conn: conn, scope: scope, today: today} do
    vehicle_fixture(scope, %{"inspection_expires_on" => in_days(today, -1)})

    {:ok, _lv, html} = live(conn, ~p"/")

    assert html =~ "期限超過"
    assert html =~ ~p"/management/alerts?#{%{"within" => "overdue"}}"
  end

  test "管理者は拠点で絞り込める", %{conn: conn, admin: admin, other_scope: other_scope, today: today} do
    vehicle_fixture(other_scope, %{
      "plate_number" => "練馬500さ77",
      "inspection_expires_on" => in_days(today, 5)
    })

    conn = log_in_user(conn, admin)

    {:ok, _lv, html} = live(conn, ~p"/management/alerts")

    assert html =~ "練馬500さ77"
    assert html =~ "B営業所"
  end
end
