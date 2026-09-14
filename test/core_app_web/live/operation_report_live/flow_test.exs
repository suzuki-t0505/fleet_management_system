defmodule CoreAppWeb.OperationReportLive.FlowTest do
  use CoreAppWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import CoreApp.AccountsFixtures
  import CoreApp.DriversFixtures
  import CoreApp.OfficesFixtures
  import CoreApp.OperationReportsFixtures
  import CoreApp.VehiclesFixtures

  alias CoreApp.Accounts.Scope
  alias CoreApp.OperationReports
  alias CoreApp.Utils.ConvertDatetime

  setup %{conn: conn} do
    office = office_fixture(%{"name" => "A営業所"})
    other_office = office_fixture(%{"name" => "B営業所"})

    manager_user = manager_fixture(%{office_id: office.id})
    manager = Scope.for_user(manager_user)

    member_user = user_fixture(%{office_id: office.id})
    member_driver = driver_fixture(manager, %{"user_id" => member_user.id, "name" => "運転 太郎"})
    member = %{Scope.for_user(member_user) | driver_id: member_driver.id}

    vehicle = vehicle_fixture(manager, %{"plate_number" => "品川100あ7001"})

    %{
      conn: conn,
      office: office,
      other_office: other_office,
      manager_user: manager_user,
      manager: manager,
      member_user: member_user,
      member: member,
      member_driver: member_driver,
      vehicle: vehicle
    }
  end

  defp form_attrs(vehicle, driver, overrides \\ %{}) do
    today = ConvertDatetime.today()
    departed = DateTime.new!(today, ~T[00:00:00]) |> DateTime.add(-6, :hour)

    Enum.into(overrides, %{
      "operation_date" => Date.to_iso8601(today),
      "vehicle_id" => vehicle.id,
      "driver_id" => driver.id,
      "departed_at" => departed |> DateTime.to_naive() |> NaiveDateTime.to_iso8601(),
      "returned_at" =>
        departed |> DateTime.add(6, :hour) |> DateTime.to_naive() |> NaiveDateTime.to_iso8601(),
      "start_odometer" => "5000",
      "end_odometer" => "5150",
      "destination" => "東京都江東区"
    })
  end

  describe "運転者：作成と提出" do
    test "日報を作成して提出できる", %{
      conn: conn,
      member_user: user,
      vehicle: vehicle,
      member_driver: driver
    } do
      conn = log_in_user(conn, user)
      {:ok, lv, _html} = live(conn, ~p"/operation_reports/new")

      assert {:ok, _show_lv, html} =
               lv
               |> form("#operation-report-form", operation_report: form_attrs(vehicle, driver))
               |> render_submit(%{"action" => "submit"})
               |> follow_redirect(conn)

      assert html =~ "日報を提出しました"
      assert html =~ "提出済み"
      assert html =~ "150 km"
    end

    test "下書き保存では提出済みにならない", %{
      conn: conn,
      member_user: user,
      vehicle: vehicle,
      member_driver: driver
    } do
      conn = log_in_user(conn, user)
      {:ok, lv, _html} = live(conn, ~p"/operation_reports/new")

      assert {:ok, _show_lv, html} =
               lv
               |> form("#operation-report-form", operation_report: form_attrs(vehicle, driver))
               |> render_submit(%{"action" => "draft"})
               |> follow_redirect(conn)

      assert html =~ "日報を下書き保存しました"
      assert html =~ "下書き"
    end

    test "V-10 オドメーターの逆転はエラーになる", %{
      conn: conn,
      member_user: user,
      vehicle: vehicle,
      member_driver: driver
    } do
      {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/operation_reports/new")

      html =
        lv
        |> form("#operation-report-form",
          operation_report: form_attrs(vehicle, driver, %{"end_odometer" => "4000"})
        )
        |> render_submit(%{"action" => "draft"})

      assert html =~ "は出発時の走行距離計以上の値を入力してください"
    end

    test "運転者が紐付いていない場合は案内が表示される", %{conn: conn, office: office} do
      user = user_fixture(%{office_id: office.id})

      {:ok, _lv, html} = conn |> log_in_user(user) |> live(~p"/operation_reports")

      assert html =~ "運転者台帳と紐付いていないため"

      # 「日報を作成できません」という案内文に含まれるため、リンクの有無で判定する
      refute html =~ ~s(href="/operation_reports/new")
    end
  end

  describe "運転者：一覧と詳細" do
    test "自分の日報のみ表示される", %{
      conn: conn,
      member_user: user,
      manager: manager,
      vehicle: vehicle,
      member_driver: member_driver
    } do
      mine = report_fixture(manager, vehicle, member_driver, %{"destination" => "自分の運行"})
      other_driver = driver_fixture(manager, %{"name" => "別の運転者"})

      other =
        report_fixture(manager, vehicle, other_driver, %{
          "start_odometer" => "90000",
          "end_odometer" => "90100",
          "destination" => "他人の運行"
        })

      {:ok, _lv, html} = conn |> log_in_user(user) |> live(~p"/operation_reports")

      assert mine.id
      assert html =~ vehicle.plate_number
      refute html =~ "他人の運行"

      assert_raise Ecto.NoResultsError, fn ->
        conn |> log_in_user(user) |> live(~p"/operation_reports/#{other}")
      end
    end

    test "差し戻された日報が一覧の上部に表示される", %{
      conn: conn,
      member_user: user,
      member: member,
      manager: manager,
      vehicle: vehicle,
      member_driver: driver
    } do
      report = submitted_report_fixture(member, vehicle, driver)
      {:ok, _rejected} = OperationReports.reject_report(manager, report, "距離を確認してください")

      {:ok, _lv, html} = conn |> log_in_user(user) |> live(~p"/operation_reports")

      assert html =~ "差し戻された日報があります"
      assert html =~ "距離を確認してください"
    end

    test "提出済みの日報には編集ボタンが出ない", %{
      conn: conn,
      member_user: user,
      member: member,
      vehicle: vehicle,
      member_driver: driver
    } do
      report = submitted_report_fixture(member, vehicle, driver)

      {:ok, _lv, html} = conn |> log_in_user(user) |> live(~p"/operation_reports/#{report}")

      refute html =~ "/operation_reports/#{report.id}/edit"
    end
  end

  describe "運行管理者：承認と差戻し" do
    test "提出済みの日報を承認できる", %{
      conn: conn,
      manager_user: manager_user,
      member: member,
      vehicle: vehicle,
      member_driver: driver
    } do
      report = submitted_report_fixture(member, vehicle, driver)

      {:ok, lv, _html} =
        conn |> log_in_user(manager_user) |> live(~p"/management/operation_reports/#{report}")

      html = lv |> element("button", "承認する") |> render_click()

      assert html =~ "承認済み"
      assert html =~ "日報を承認しました"
    end

    test "差戻しには理由が必要", %{
      conn: conn,
      manager_user: manager_user,
      member: member,
      vehicle: vehicle,
      member_driver: driver
    } do
      report = submitted_report_fixture(member, vehicle, driver)

      {:ok, lv, _html} =
        conn |> log_in_user(manager_user) |> live(~p"/management/operation_reports/#{report}")

      lv |> element("button", "差し戻す") |> render_click()

      html = lv |> form("#reject-form", %{"rejected_reason" => ""}) |> render_submit()
      assert html =~ "差戻しの理由を入力してください"

      html = lv |> form("#reject-form", %{"rejected_reason" => "距離を確認"}) |> render_submit()
      assert html =~ "日報を差し戻しました"
      assert html =~ "差戻し中"
    end

    test "下書きの日報には承認ボタンが出ない", %{
      conn: conn,
      manager_user: manager_user,
      member: member,
      vehicle: vehicle,
      member_driver: driver
    } do
      report = report_fixture(member, vehicle, driver)

      {:ok, _lv, html} =
        conn |> log_in_user(manager_user) |> live(~p"/management/operation_reports/#{report}")

      refute html =~ "承認する"
    end

    test "未承認のみに絞り込める", %{
      conn: conn,
      manager_user: manager_user,
      member: member,
      manager: manager,
      vehicle: vehicle,
      member_driver: driver
    } do
      submitted_report_fixture(member, vehicle, driver, %{"destination" => "提出済みの運行"})

      report_fixture(manager, vehicle, driver, %{
        "start_odometer" => "80000",
        "end_odometer" => "80100",
        "destination" => "下書きの運行"
      })

      {:ok, _lv, html} =
        conn
        |> log_in_user(manager_user)
        |> live(~p"/management/operation_reports?#{%{"status" => "submitted"}}")

      assert html =~ "提出済み"
      refute html =~ "下書き</span>"
    end

    test "運行管理者はオドメーター逆転を警告として保存できる", %{
      conn: conn,
      manager_user: manager_user,
      manager: manager,
      vehicle: vehicle,
      member_driver: driver
    } do
      report = report_fixture(manager, vehicle, driver)

      conn = log_in_user(conn, manager_user)
      {:ok, lv, _html} = live(conn, ~p"/management/operation_reports/#{report}/edit")

      html =
        lv
        |> form("#operation-report-form", operation_report: %{"end_odometer" => "1"})
        |> render_change()

      assert html =~ "走行距離は0kmとして記録されます"

      assert {:ok, _show_lv, html} =
               lv
               |> form("#operation-report-form",
                 operation_report: %{"end_odometer" => "1", "note" => "メーター交換"}
               )
               |> render_submit()
               |> follow_redirect(conn)

      assert html =~ "日報を更新しました"
      assert html =~ "0 km"
    end
  end

  describe "ダッシュボード" do
    test "運転者には未提出と差戻しの件数が出る", %{
      conn: conn,
      member_user: user,
      member: member,
      manager: manager,
      vehicle: vehicle,
      member_driver: driver
    } do
      report_fixture(member, vehicle, driver)

      rejected =
        submitted_report_fixture(member, vehicle, driver, %{
          "start_odometer" => "60000",
          "end_odometer" => "60100"
        })

      {:ok, _} = OperationReports.reject_report(manager, rejected, "確認してください")

      {:ok, _lv, html} = conn |> log_in_user(user) |> live(~p"/")

      assert html =~ "未提出の日報"
      assert html =~ "差し戻された日報"
    end

    test "運行管理者には未承認の件数が出る", %{
      conn: conn,
      manager_user: manager_user,
      member: member,
      vehicle: vehicle,
      member_driver: driver
    } do
      submitted_report_fixture(member, vehicle, driver)

      conn = log_in_user(conn, manager_user)
      {:ok, lv, html} = live(conn, ~p"/")

      assert html =~ "未承認の日報"

      assert {:ok, _index_lv, index_html} =
               lv |> element("a", "未承認の日報") |> render_click() |> follow_redirect(conn)

      assert index_html =~ "提出済み"
    end
  end

  describe "認可" do
    test "一般利用者は管理画面にアクセスできない", %{conn: conn, member_user: user} do
      assert {:error, {:redirect, %{to: "/", flash: flash}}} =
               conn |> log_in_user(user) |> live(~p"/management/operation_reports")

      assert flash["error"] == "このページを表示する権限がありません"
    end

    test "他拠点の運行管理者は日報を参照できない", %{
      conn: conn,
      manager: manager,
      vehicle: vehicle,
      member_driver: driver,
      other_office: other_office
    } do
      report = report_fixture(manager, vehicle, driver)
      other_manager = manager_fixture(%{office_id: other_office.id})

      assert_raise Ecto.NoResultsError, fn ->
        conn
        |> log_in_user(other_manager)
        |> live(~p"/management/operation_reports/#{report}")
      end
    end
  end
end
