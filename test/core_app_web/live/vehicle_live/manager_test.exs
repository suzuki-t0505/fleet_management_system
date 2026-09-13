defmodule CoreAppWeb.VehicleLive.ManagerTest do
  use CoreAppWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import CoreApp.AccountsFixtures
  import CoreApp.OfficesFixtures
  import CoreApp.VehiclesFixtures

  alias CoreApp.Accounts.Scope
  alias CoreApp.Vehicles

  setup %{conn: conn} do
    office_a = office_fixture(%{"name" => "A営業所"})
    office_b = office_fixture(%{"name" => "B営業所"})

    manager = manager_fixture(%{office_id: office_a.id})
    admin = admin_fixture(%{office_id: office_a.id})

    %{
      conn: log_in_user(conn, manager),
      manager: manager,
      manager_scope: Scope.for_user(manager),
      admin: admin,
      office_a: office_a,
      office_b: office_b
    }
  end

  describe "一覧" do
    test "自拠点の車両が表示される", %{conn: conn, manager_scope: scope, office_b: office_b} do
      mine = vehicle_fixture(scope, %{"plate_number" => "品川100あ1", "model_name" => "エルフ"})

      other_scope = Scope.for_user(manager_fixture(%{office_id: office_b.id}))
      other = vehicle_fixture(other_scope, %{"plate_number" => "練馬500さ2"})

      {:ok, _lv, html} = live(conn, ~p"/management/vehicles")

      assert html =~ mine.plate_number
      refute html =~ other.plate_number
    end

    test "車両が無いときは空状態を表示する", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/management/vehicles")

      assert html =~ "条件に一致する車両がありません"
    end

    test "キーワードで絞り込める", %{conn: conn, manager_scope: scope} do
      vehicle_fixture(scope, %{"plate_number" => "品川100あ11", "model_name" => "エルフ"})
      vehicle_fixture(scope, %{"plate_number" => "練馬500さ22", "model_name" => "キャンター"})

      {:ok, lv, _html} = live(conn, ~p"/management/vehicles")

      html = lv |> form("#search-bar", %{"q" => "キャンター"}) |> render_change()

      assert html =~ "練馬500さ22"
      refute html =~ "品川100あ11"
    end

    test "廃車は既定で表示されず、ステータス指定で表示される", %{conn: conn, manager_scope: scope} do
      vehicle = vehicle_fixture(scope, %{"plate_number" => "品川100あ33"})
      {:ok, _} = Vehicles.update_vehicle(scope, vehicle, %{"status" => "scrapped"})

      {:ok, lv, html} = live(conn, ~p"/management/vehicles")
      refute html =~ "品川100あ33"

      html = lv |> form("#search-bar", %{"status" => "scrapped"}) |> render_change()
      assert html =~ "品川100あ33"
    end

    test "運行管理者に拠点の絞り込みは表示されない", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/management/vehicles")

      refute html =~ "filter-office_id"
    end

    test "管理者には拠点の絞り込みが表示される", %{conn: conn, admin: admin} do
      {:ok, _lv, html} = conn |> log_in_user(admin) |> live(~p"/management/vehicles")

      assert html =~ "filter-office_id"
    end
  end

  describe "登録" do
    test "車両を登録すると詳細画面に遷移し、一覧に表示される", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/management/vehicles/new")

      attrs = %{
        "plate_number" => "品川100あ4444",
        "vin" => "VIN-4444",
        "vehicle_class" => "medium",
        "maker" => "いすゞ",
        "model_name" => "エルフ",
        "first_registered_on" => "2021-04-01",
        "status" => "active",
        "inspection_expires_on" => "2027-03-31",
        "liability_insurance_expires_on" => "2027-04-30"
      }

      assert {:ok, _show_lv, html} =
               lv
               |> form("#vehicle-form", vehicle: attrs)
               |> render_submit()
               |> follow_redirect(conn)

      assert html =~ "車両を登録しました"
      assert html =~ "品川100あ4444"

      {:ok, _index_lv, index_html} = live(conn, ~p"/management/vehicles")
      assert index_html =~ "品川100あ4444"
    end

    test "重複する車両番号はエラーになる", %{conn: conn, manager_scope: scope} do
      vehicle_fixture(scope, %{"plate_number" => "品川100あ5555"})

      {:ok, lv, _html} = live(conn, ~p"/management/vehicles/new")

      html =
        lv
        |> form("#vehicle-form",
          vehicle: %{
            "plate_number" => "品川100あ5555",
            "vin" => "VIN-5555",
            "vehicle_class" => "medium",
            "maker" => "いすゞ",
            "model_name" => "エルフ",
            "first_registered_on" => "2021-04-01",
            "status" => "active",
            "inspection_expires_on" => "2027-03-31",
            "liability_insurance_expires_on" => "2027-04-30"
          }
        )
        |> render_submit()

      assert html =~ "この車両番号は既に登録されています"
    end

    test "必須項目が空だとエラーを表示する", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/management/vehicles/new")

      html = lv |> form("#vehicle-form", vehicle: %{"plate_number" => ""}) |> render_change()

      assert html =~ "can&#39;t be blank"
    end
  end

  describe "編集" do
    test "更新すると詳細に反映される", %{conn: conn, manager_scope: scope} do
      vehicle = vehicle_fixture(scope, %{"model_name" => "エルフ"})

      {:ok, lv, _html} = live(conn, ~p"/management/vehicles/#{vehicle}/edit")

      assert {:ok, _show_lv, html} =
               lv
               |> form("#vehicle-form", vehicle: %{"model_name" => "フォワード"})
               |> render_submit()
               |> follow_redirect(conn)

      assert html =~ "車両を更新しました"
      assert html =~ "フォワード"
    end

    test "廃車にすると一覧から消える", %{conn: conn, manager_scope: scope} do
      vehicle = vehicle_fixture(scope, %{"plate_number" => "品川100あ6666"})

      {:ok, lv, _html} = live(conn, ~p"/management/vehicles/#{vehicle}/edit")

      assert {:ok, _show_lv, _html} =
               lv
               |> form("#vehicle-form", vehicle: %{"status" => "scrapped"})
               |> render_submit()
               |> follow_redirect(conn)

      {:ok, _index_lv, index_html} = live(conn, ~p"/management/vehicles")
      refute index_html =~ "品川100あ6666"
    end
  end

  describe "詳細" do
    test "車両の情報と期限が表示される", %{conn: conn, manager_scope: scope} do
      vehicle = vehicle_fixture(scope, %{"model_name" => "エルフ"})

      {:ok, _lv, html} = live(conn, ~p"/management/vehicles/#{vehicle}")

      assert html =~ vehicle.plate_number
      assert html =~ "エルフ"
      assert html =~ "車検満了日"
      assert html =~ "履歴"
    end
  end

  describe "スコープ境界" do
    test "他拠点の車両の詳細は404になる", %{conn: conn, office_b: office_b} do
      other_scope = Scope.for_user(manager_fixture(%{office_id: office_b.id}))
      other = vehicle_fixture(other_scope)

      assert_raise Ecto.NoResultsError, fn ->
        live(conn, ~p"/management/vehicles/#{other}")
      end
    end

    test "他拠点の車両の編集画面も404になる", %{conn: conn, office_b: office_b} do
      other_scope = Scope.for_user(manager_fixture(%{office_id: office_b.id}))
      other = vehicle_fixture(other_scope)

      assert_raise Ecto.NoResultsError, fn ->
        live(conn, ~p"/management/vehicles/#{other}/edit")
      end
    end
  end
end
