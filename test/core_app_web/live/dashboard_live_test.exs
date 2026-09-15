defmodule CoreAppWeb.DashboardLiveTest do
  use CoreAppWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import CoreApp.AccountsFixtures
  import CoreApp.DriversFixtures
  import CoreApp.OfficesFixtures
  import CoreApp.OperationReportsFixtures
  import CoreApp.VehiclesFixtures

  alias CoreApp.Accounts.Scope
  alias CoreApp.OperationReports

  describe "未ログイン" do
    test "ログイン画面にリダイレクトする", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/")
    end
  end

  describe "一般利用者" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "ダッシュボードが表示される", %{conn: conn, user: user} do
      {:ok, _lv, html} = live(conn, ~p"/")

      assert html =~ "ダッシュボード"
      assert html =~ user.name
      assert html =~ "一般利用者"
    end

    test "管理者・運行管理者向けのナビゲーションは表示されない", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/")

      assert html =~ "運行日報"
      refute html =~ "運転者"
      refute html =~ "監査ログ"
    end

    test "直近7日の日報と直近に運転した車両が表示される", %{conn: conn, user: user} do
      manager = manager_fixture(%{office_id: user.office_id}) |> Scope.for_user()
      vehicle = vehicle_fixture(manager, %{"plate_number" => "品川100あ55"})
      driver = driver_fixture(manager, %{"user_id" => user.id})
      scope = user |> CoreApp.Repo.preload(:driver) |> Scope.for_user()

      report_fixture(scope, vehicle, driver, %{
        "start_odometer" => "1000",
        "end_odometer" => "1080"
      })

      {:ok, _lv, html} = live(conn, ~p"/")

      assert html =~ "直近7日の日報"
      assert html =~ "品川100あ55"
      assert html =~ "直近に運転した車両"
      assert html =~ "80 km"
    end
  end

  describe "運行管理者" do
    setup %{conn: conn} do
      user = manager_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "運行管理者向けのナビゲーションが表示される", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/")

      assert html =~ "運転者"
      assert html =~ "点検整備"
      assert html =~ "期限アラート"
      assert html =~ "運行管理者"
      refute html =~ "監査ログ"
    end
  end

  describe "運行管理者の当月実績" do
    setup %{conn: conn} do
      office = office_fixture()
      manager = manager_fixture(%{office_id: office.id})
      scope = Scope.for_user(manager)

      %{conn: log_in_user(conn, manager), scope: scope, office: office}
    end

    test "承認済みの日報だけが当月の実績に反映される", %{conn: conn, scope: scope} do
      vehicle = vehicle_fixture(scope)
      driver = driver_fixture(scope)

      report =
        submitted_report_fixture(scope, vehicle, driver, %{
          "start_odometer" => "1000",
          "end_odometer" => "1300"
        })

      {:ok, _approved} = OperationReports.approve_report(scope, report)

      {:ok, _lv, html} = live(conn, ~p"/")

      assert html =~ "当月の実績"
      assert html =~ "1 台"
      assert html =~ "300 km"
    end
  end

  describe "管理者" do
    setup %{conn: conn} do
      user = admin_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "すべてのナビゲーションが表示される", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/")

      assert html =~ "運転者"
      assert html =~ "監査ログ"
      assert html =~ "拠点"
    end

    test "拠点別の内訳が表示される", %{conn: conn} do
      other_office = office_fixture(%{"name" => "大阪営業所"})
      manager = manager_fixture(%{office_id: other_office.id}) |> Scope.for_user()
      vehicle = vehicle_fixture(manager)
      driver = driver_fixture(manager)

      report =
        submitted_report_fixture(manager, vehicle, driver, %{
          "start_odometer" => "1000",
          "end_odometer" => "1420"
        })

      {:ok, _approved} = OperationReports.approve_report(manager, report)

      {:ok, _lv, html} = live(conn, ~p"/")

      assert html =~ "拠点別の内訳"
      assert html =~ "大阪営業所"
      assert html =~ "420 km"
      assert html =~ "未完了の改善報告"
    end
  end
end
