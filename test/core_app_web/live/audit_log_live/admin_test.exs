defmodule CoreAppWeb.AuditLogLive.AdminTest do
  use CoreAppWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import CoreApp.AccountsFixtures
  import CoreApp.OfficesFixtures
  import CoreApp.VehiclesFixtures

  alias CoreApp.Accounts.Scope

  setup %{conn: conn} do
    office = office_fixture()
    admin = admin_fixture(%{office_id: office.id, name: "管理 太郎"})
    scope = Scope.for_user(admin)

    %{conn: log_in_user(conn, admin), admin: admin, scope: scope, office: office}
  end

  test "台帳の変更が記録され、一覧に表示される", %{conn: conn, scope: scope, office: office} do
    vehicle = vehicle_fixture(scope, %{"office_id" => office.id, "plate_number" => "品川100あ88"})

    {:ok, _lv, html} = live(conn, ~p"/management/audit_logs")

    assert html =~ "車両"
    assert html =~ "登録"
    assert html =~ vehicle.id
    assert html =~ "plate_number: 品川100あ88"
  end

  test "対象と操作で絞り込める", %{conn: conn, scope: scope, office: office} do
    vehicle = vehicle_fixture(scope, %{"office_id" => office.id})
    {:ok, _updated} = CoreApp.Vehicles.update_vehicle(scope, vehicle, %{"status" => "idle"})

    {:ok, lv, _html} = live(conn, ~p"/management/audit_logs")

    html = lv |> form("#search-bar", %{"action" => "update"}) |> render_change()

    assert html =~ "status: idle"
    refute html =~ "plate_number"

    html =
      lv |> form("#search-bar", %{"action" => "", "resource_type" => "user"}) |> render_change()

    assert html =~ "条件に一致する監査ログがありません"
  end

  test "記録が無いときは空状態を表示する", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/management/audit_logs")

    assert html =~ "条件に一致する監査ログがありません"
  end

  describe "アクセス制御" do
    test "運行管理者は参照できない", %{conn: conn, office: office} do
      manager = manager_fixture(%{office_id: office.id})

      assert {:error, {:redirect, %{to: "/", flash: flash}}} =
               conn |> log_in_user(manager) |> live(~p"/management/audit_logs")

      assert flash["error"] == "このページを表示する権限がありません"
    end
  end
end
