defmodule CoreAppWeb.MaintenanceLive.ManagerTest do
  use CoreAppWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import CoreApp.AccountsFixtures
  import CoreApp.MaintenancesFixtures
  import CoreApp.OfficesFixtures
  import CoreApp.VehiclesFixtures

  alias CoreApp.Accounts.Scope
  alias CoreApp.Utils.ConvertDatetime
  alias CoreApp.Vehicles

  setup %{conn: conn} do
    office_a = office_fixture(%{"name" => "A営業所"})
    office_b = office_fixture(%{"name" => "B営業所"})

    manager = manager_fixture(%{office_id: office_a.id})
    scope = Scope.for_user(manager)
    other_scope = Scope.for_user(manager_fixture(%{office_id: office_b.id}))

    %{
      conn: log_in_user(conn, manager),
      scope: scope,
      other_scope: other_scope,
      vehicle: vehicle_fixture(scope, %{"plate_number" => "品川100あ100"}),
      other_vehicle: vehicle_fixture(other_scope, %{"plate_number" => "練馬500さ200"}),
      today: ConvertDatetime.today()
    }
  end

  describe "一覧" do
    test "自拠点の記録だけが表示される", %{
      conn: conn,
      scope: scope,
      other_scope: other_scope,
      vehicle: vehicle,
      other_vehicle: other_vehicle
    } do
      maintenance_fixture(scope, vehicle, %{"vendor" => "自拠点の工場"})
      maintenance_fixture(other_scope, other_vehicle, %{"vendor" => "他拠点の工場"})

      {:ok, _lv, html} = live(conn, ~p"/management/maintenances")

      assert html =~ "自拠点の工場"
      refute html =~ "他拠点の工場"
    end

    test "記録が無いときは空状態を表示する", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/management/maintenances")

      assert html =~ "条件に一致する点検整備記録がありません"
    end

    test "区分で絞り込める", %{conn: conn, scope: scope, vehicle: vehicle} do
      maintenance_fixture(scope, vehicle, %{"category" => "oil", "vendor" => "オイルの店"})
      maintenance_fixture(scope, vehicle, %{"category" => "tire", "vendor" => "タイヤの店"})

      {:ok, lv, _html} = live(conn, ~p"/management/maintenances")

      html = lv |> form("#search-bar", %{"category" => "tire"}) |> render_change()

      assert html =~ "タイヤの店"
      refute html =~ "オイルの店"
    end
  end

  describe "登録" do
    test "車検を登録すると車両の車検満了日が更新される", %{
      conn: conn,
      scope: scope,
      vehicle: vehicle,
      today: today
    } do
      next = Date.add(today, 730)

      {:ok, lv, _html} = live(conn, ~p"/management/maintenances/new")

      assert {:ok, _show_lv, html} =
               lv
               |> form("#maintenance-form",
                 maintenance: %{
                   "vehicle_id" => vehicle.id,
                   "performed_on" => Date.to_iso8601(today),
                   "category" => "inspection",
                   "odometer" => "30000",
                   "vendor" => "車検の工場",
                   "next_scheduled_on" => Date.to_iso8601(next)
                 }
               )
               |> render_submit()
               |> follow_redirect(conn)

      assert html =~ "点検整備記録を登録しました"
      assert html =~ "車検の工場"
      assert Vehicles.get_vehicle!(scope, vehicle.id).inspection_expires_on == next
    end

    test "車検で次回満了日が無いとエラーになる", %{conn: conn, vehicle: vehicle, today: today} do
      {:ok, lv, _html} = live(conn, ~p"/management/maintenances/new")

      html =
        lv
        |> form("#maintenance-form",
          maintenance: %{
            "vehicle_id" => vehicle.id,
            "performed_on" => Date.to_iso8601(today),
            "category" => "inspection",
            "odometer" => "30000",
            "vendor" => "車検の工場"
          }
        )
        |> render_submit()

      assert html =~ "新しい車検満了日"
    end

    test "区分に応じて次回予定日のラベルが変わる", %{conn: conn, vehicle: vehicle} do
      {:ok, lv, html} = live(conn, ~p"/management/maintenances/new")

      assert html =~ "次回実施予定日"

      html =
        lv
        |> form("#maintenance-form",
          maintenance: %{"vehicle_id" => vehicle.id, "category" => "periodic_3m"}
        )
        |> render_change()

      assert html =~ "次回3ヶ月点検の予定日"
    end

    test "車両詳細から車両を選んだ状態で開ける", %{conn: conn, vehicle: vehicle, today: today} do
      {:ok, lv, _html} =
        live(conn, ~p"/management/maintenances/new?#{%{"vehicle_id" => vehicle.id}}")

      # 車両を指定せずに保存でき、選択済みの車両の記録になる
      assert {:ok, _show_lv, html} =
               lv
               |> form("#maintenance-form",
                 maintenance: %{
                   "performed_on" => Date.to_iso8601(today),
                   "category" => "oil",
                   "odometer" => "1000",
                   "vendor" => "導線の工場"
                 }
               )
               |> render_submit()
               |> follow_redirect(conn)

      assert html =~ "導線の工場"
      assert html =~ vehicle.plate_number
    end

    test "他拠点の車両は選択肢に出ない", %{conn: conn, other_vehicle: other_vehicle} do
      {:ok, _lv, html} = live(conn, ~p"/management/maintenances/new")

      refute html =~ other_vehicle.plate_number
    end
  end

  describe "詳細" do
    test "記録の内容を表示する", %{conn: conn, scope: scope, vehicle: vehicle} do
      maintenance = maintenance_fixture(scope, vehicle, %{"vendor" => "詳細の工場"})

      {:ok, _lv, html} = live(conn, ~p"/management/maintenances/#{maintenance}")

      assert html =~ "詳細の工場"
      assert html =~ vehicle.plate_number
      assert html =~ "12,000 km"
    end

    test "他拠点の記録は開けない", %{conn: conn, other_scope: other_scope, other_vehicle: vehicle} do
      maintenance = maintenance_fixture(other_scope, vehicle)

      assert_raise Ecto.NoResultsError, fn ->
        live(conn, ~p"/management/maintenances/#{maintenance}")
      end
    end
  end

  describe "車両詳細からの導線" do
    test "点検整備履歴が表示される", %{conn: conn, scope: scope, vehicle: vehicle} do
      maintenance_fixture(scope, vehicle, %{"vendor" => "履歴の工場"})

      {:ok, _lv, html} = live(conn, ~p"/management/vehicles/#{vehicle}")

      assert html =~ "点検整備履歴"
      assert html =~ "履歴の工場"
    end
  end
end
