defmodule CoreAppWeb.IncidentLive.ManagerTest do
  use CoreAppWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import CoreApp.AccountsFixtures
  import CoreApp.IncidentsFixtures
  import CoreApp.OfficesFixtures
  import CoreApp.VehiclesFixtures

  alias CoreApp.Accounts.Scope
  alias CoreApp.Incidents

  setup %{conn: conn} do
    office = office_fixture(%{"name" => "A営業所"})
    other_office = office_fixture(%{"name" => "B営業所"})

    manager = manager_fixture(%{office_id: office.id, name: "運行 花子"})
    scope = Scope.for_user(manager)
    reporter = user_fixture(%{office_id: office.id, name: "報告 太郎"}) |> Scope.for_user()

    %{
      conn: log_in_user(conn, manager),
      manager: manager,
      scope: scope,
      reporter: reporter,
      office: office,
      other_office: other_office,
      vehicle: vehicle_fixture(scope, %{"plate_number" => "品川100あ99"})
    }
  end

  describe "一覧" do
    test "自拠点の記録が表示され、区分で絞り込める", %{conn: conn, scope: scope, vehicle: vehicle} do
      incident_fixture(scope, vehicle, %{"place" => "ヒヤリの場所"})
      incident_fixture(scope, vehicle, %{"category" => "injury", "place" => "人身の場所"})

      {:ok, lv, html} = live(conn, ~p"/management/incidents")
      assert html =~ "ヒヤリの場所"
      assert html =~ "人身の場所"

      html = lv |> form("#search-bar", %{"category" => "injury"}) |> render_change()
      assert html =~ "人身の場所"
      refute html =~ "ヒヤリの場所"
    end

    test "他拠点の記録は表示されない", %{conn: conn, other_office: other_office} do
      other = manager_fixture(%{office_id: other_office.id}) |> Scope.for_user()
      other_vehicle = vehicle_fixture(other)
      incident_fixture(other, other_vehicle, %{"place" => "他拠点の場所"})

      {:ok, _lv, html} = live(conn, ~p"/management/incidents")

      refute html =~ "他拠点の場所"
    end
  end

  describe "分析と承認" do
    test "分析開始から改善策の登録まで進められる", %{conn: conn, reporter: reporter, vehicle: vehicle} do
      incident = incident_fixture(reporter, vehicle)

      {:ok, lv, _html} = live(conn, ~p"/management/incidents/#{incident}")

      html = lv |> element("button", "原因分析を開始") |> render_click()
      assert html =~ "原因分析を開始しました"
      assert html =~ "分析中"

      html =
        lv
        |> form("#countermeasure-form",
          incident: %{
            "direct_cause" => "車間距離が不足していた",
            "countermeasure" => "朝礼で周知する",
            "countermeasure_owner" => "運行 花子"
          }
        )
        |> render_submit()

      assert html =~ "改善策を登録しました"
      assert html =~ "改善策登録済み"
    end

    test "直接原因が空だと改善策を登録できない", %{
      conn: conn,
      scope: scope,
      reporter: reporter,
      vehicle: vehicle
    } do
      incident = incident_fixture(reporter, vehicle)
      {:ok, incident} = Incidents.start_analysis(scope, incident)

      {:ok, lv, _html} = live(conn, ~p"/management/incidents/#{incident}")

      html =
        lv
        |> form("#countermeasure-form", incident: %{"countermeasure" => "対策だけ書いた"})
        |> render_submit()

      assert html =~ "を入力してください"
    end

    test "V-26 報告者本人には承認ボタンが出ない", %{conn: conn, scope: scope, vehicle: vehicle} do
      incident = countermeasure_reported_fixture(scope, vehicle)

      {:ok, _lv, html} = live(conn, ~p"/management/incidents/#{incident}")

      refute html =~ "承認する"
      assert html =~ "報告者本人は承認・差戻しができません"
    end

    test "報告者以外は承認できる", %{conn: conn, scope: scope, reporter: reporter, vehicle: vehicle} do
      incident = awaiting_approval(reporter, scope, vehicle)

      {:ok, lv, html} = live(conn, ~p"/management/incidents/#{incident}")
      assert html =~ "承認する"

      html = lv |> element("button", "承認する") |> render_click()

      assert html =~ "改善報告を承認しました"
      assert html =~ "完了"
    end

    test "差し戻すと分析中に戻る", %{conn: conn, scope: scope, reporter: reporter, vehicle: vehicle} do
      incident = awaiting_approval(reporter, scope, vehicle)

      {:ok, lv, _html} = live(conn, ~p"/management/incidents/#{incident}")

      html = lv |> element("button", "差し戻す") |> render_click()

      assert html =~ "分析中に差し戻しました"
    end
  end

  # 一般利用者が報告し、運行管理者が改善策まで登録した状態を作る
  defp awaiting_approval(reporter, analyst, vehicle) do
    incident = incident_fixture(reporter, vehicle)
    {:ok, incident} = Incidents.start_analysis(analyst, incident)

    {:ok, incident} =
      Incidents.report_countermeasure(analyst, incident, %{
        "direct_cause" => "車間距離が不足していた",
        "countermeasure" => "朝礼で周知する"
      })

    incident
  end

  describe "全社共有" do
    test "管理者だけが全社共有を切り替えられる", %{conn: conn, office: office} = ctx do
      incident = incident_fixture(ctx.scope, ctx.vehicle)

      {:ok, _lv, html} = live(conn, ~p"/management/incidents/#{incident}")
      refute html =~ "全社共有する"

      admin = admin_fixture(%{office_id: office.id})
      {:ok, lv, html} = conn |> log_in_user(admin) |> live(~p"/management/incidents/#{incident}")
      assert html =~ "全社共有する"

      html = lv |> element("button", "全社共有する") |> render_click()

      assert html =~ "全社共有を開始しました"
      assert html =~ "全社共有中"
    end
  end

  describe "アクセス制御" do
    test "一般利用者は管理者向け画面を開けない", %{conn: conn, office: office} do
      member = user_fixture(%{office_id: office.id})

      assert {:error, {:redirect, %{to: "/", flash: flash}}} =
               conn |> log_in_user(member) |> live(~p"/management/incidents")

      assert flash["error"] == "このページを表示する権限がありません"
    end
  end
end
