defmodule CoreAppWeb.VehicleLive.MemberTest do
  use CoreAppWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import CoreApp.AccountsFixtures
  import CoreApp.OfficesFixtures
  import CoreApp.VehiclesFixtures

  alias CoreApp.Accounts.Scope

  setup %{conn: conn} do
    office_a = office_fixture(%{"name" => "A営業所"})
    office_b = office_fixture(%{"name" => "B営業所"})

    member = user_fixture(%{office_id: office_a.id})
    manager_a = Scope.for_user(manager_fixture(%{office_id: office_a.id}))
    manager_b = Scope.for_user(manager_fixture(%{office_id: office_b.id}))

    %{
      conn: log_in_user(conn, member),
      member: member,
      manager_a: manager_a,
      manager_b: manager_b
    }
  end

  describe "一覧" do
    test "自拠点の車両を参照できる", %{conn: conn, manager_a: scope_a, manager_b: scope_b} do
      mine = vehicle_fixture(scope_a, %{"plate_number" => "品川100あ71"})
      other = vehicle_fixture(scope_b, %{"plate_number" => "練馬500さ72"})

      {:ok, _lv, html} = live(conn, ~p"/vehicles")

      assert html =~ mine.plate_number
      refute html =~ other.plate_number
    end

    test "編集の導線が表示されない", %{conn: conn, manager_a: scope} do
      vehicle_fixture(scope)

      {:ok, _lv, html} = live(conn, ~p"/vehicles")

      refute html =~ "車両を登録"
      refute html =~ "/management/vehicles"
    end

    test "キーワードで絞り込める", %{conn: conn, manager_a: scope} do
      vehicle_fixture(scope, %{"plate_number" => "品川100あ73", "model_name" => "エルフ"})
      vehicle_fixture(scope, %{"plate_number" => "練馬500さ74", "model_name" => "キャンター"})

      {:ok, lv, _html} = live(conn, ~p"/vehicles")

      html = lv |> form("#search-bar", %{"q" => "エルフ"}) |> render_change()

      assert html =~ "品川100あ73"
      refute html =~ "練馬500さ74"
    end
  end

  describe "詳細" do
    test "自拠点の車両を参照でき、編集ボタンが無い", %{conn: conn, manager_a: scope} do
      vehicle = vehicle_fixture(scope)

      {:ok, _lv, html} = live(conn, ~p"/vehicles/#{vehicle}")

      assert html =~ vehicle.plate_number
      assert html =~ "車検満了日"
      refute html =~ "編集"
    end

    test "他拠点の車両は404になる", %{conn: conn, manager_b: scope_b} do
      other = vehicle_fixture(scope_b)

      assert_raise Ecto.NoResultsError, fn ->
        live(conn, ~p"/vehicles/#{other}")
      end
    end
  end

  describe "認可" do
    test "一般利用者は管理画面にアクセスできない", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/", flash: flash}}} =
               live(conn, ~p"/management/vehicles")

      assert flash["error"] == "このページを表示する権限がありません"
    end

    test "未ログインはログイン画面にリダイレクトされる" do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} =
               live(build_conn(), ~p"/vehicles")
    end
  end
end
