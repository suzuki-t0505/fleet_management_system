defmodule CoreAppWeb.IncidentLive.MemberTest do
  use CoreAppWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import CoreApp.AccountsFixtures
  import CoreApp.IncidentsFixtures
  import CoreApp.OfficesFixtures
  import CoreApp.VehiclesFixtures

  alias CoreApp.Accounts.Scope
  alias CoreApp.Attachments
  alias CoreApp.Incidents

  setup %{conn: conn} do
    office = office_fixture(%{"name" => "A営業所"})
    other_office = office_fixture(%{"name" => "B営業所"})

    member = user_fixture(%{office_id: office.id, name: "報告 太郎"})
    manager_scope = manager_fixture(%{office_id: office.id}) |> Scope.for_user()
    admin_scope = admin_fixture(%{office_id: office.id}) |> Scope.for_user()

    %{
      conn: log_in_user(conn, member),
      member: member,
      member_scope: Scope.for_user(member),
      manager_scope: manager_scope,
      admin_scope: admin_scope,
      other_office: other_office,
      vehicle: vehicle_fixture(manager_scope, %{"plate_number" => "品川100あ77"})
    }
  end

  defp occurred_at_input do
    DateTime.utc_now()
    |> DateTime.add(9 * 3600 - 3600, :second)
    |> DateTime.to_naive()
    |> NaiveDateTime.to_iso8601()
    |> String.slice(0, 16)
  end

  describe "報告" do
    test "報告でき、一覧と詳細に表示される", %{conn: conn, vehicle: vehicle} do
      {:ok, lv, _html} = live(conn, ~p"/incidents/new")

      assert {:ok, _show_lv, html} =
               lv
               |> form("#incident-form",
                 incident: %{
                   "occurred_at" => occurred_at_input(),
                   "category" => "near_miss",
                   "vehicle_id" => vehicle.id,
                   "place" => "港区の交差点",
                   "weather" => "rain",
                   "description" => "前方の車が急停止した"
                 }
               )
               |> render_submit()
               |> follow_redirect(conn)

      assert html =~ "事故・ヒヤリを報告しました"
      assert html =~ "港区の交差点"
      assert html =~ "ヒヤリハット"

      {:ok, _index_lv, index_html} = live(conn, ~p"/incidents")
      assert index_html =~ "港区の交差点"
    end

    test "写真を添付して報告できる", %{conn: conn, vehicle: vehicle} do
      {:ok, lv, _html} = live(conn, ~p"/incidents/new")

      photo =
        file_input(lv, "#incident-form", :files, [
          %{
            name: "現場写真.png",
            content: <<137, 80, 78, 71, 13, 10, 26, 10>> <> "image",
            type: "image/png"
          }
        ])

      assert render_upload(photo, "現場写真.png") =~ "現場写真.png"

      assert {:ok, _show_lv, html} =
               lv
               |> form("#incident-form",
                 incident: %{
                   "occurred_at" => occurred_at_input(),
                   "category" => "property",
                   "vehicle_id" => vehicle.id,
                   "place" => "港区の駐車場",
                   "weather" => "clear",
                   "description" => "壁に擦った"
                 }
               )
               |> render_submit()
               |> follow_redirect(conn)

      assert html =~ "現場写真.png"
    end

    test "未来の日時は報告できない", %{conn: conn, vehicle: vehicle} do
      future =
        DateTime.utc_now()
        |> DateTime.add(9 * 3600 + 3600, :second)
        |> DateTime.to_naive()
        |> NaiveDateTime.to_iso8601()
        |> String.slice(0, 16)

      {:ok, lv, _html} = live(conn, ~p"/incidents/new")

      html =
        lv
        |> form("#incident-form",
          incident: %{
            "occurred_at" => future,
            "category" => "near_miss",
            "vehicle_id" => vehicle.id,
            "place" => "港区",
            "weather" => "clear",
            "description" => "未来の報告"
          }
        )
        |> render_submit()

      assert html =~ "未来の日時は入力できません"
    end
  end

  describe "一覧と詳細" do
    test "他人の報告は表示されない", %{conn: conn, manager_scope: manager, vehicle: vehicle} do
      incident_fixture(manager, vehicle, %{"place" => "他人の報告した場所"})

      {:ok, _lv, html} = live(conn, ~p"/incidents")

      refute html =~ "他人の報告した場所"
      assert html =~ "条件に一致する記録がありません"
    end

    test "全社共有された記録は表示される", %{
      conn: conn,
      manager_scope: manager,
      admin_scope: admin,
      vehicle: vehicle
    } do
      incident = incident_fixture(manager, vehicle, %{"place" => "共有された場所"})
      {:ok, _shared} = Incidents.share_incident(admin, incident, true)

      {:ok, _lv, html} = live(conn, ~p"/incidents")

      assert html =~ "共有された場所"
    end

    test "他拠点の共有記録では氏名が伏せられる", %{conn: conn, admin_scope: admin} = ctx do
      other_manager = manager_fixture(%{office_id: ctx.other_office.id}) |> Scope.for_user()
      other_vehicle = vehicle_fixture(other_manager)
      incident = incident_fixture(other_manager, other_vehicle, %{"place" => "他拠点の場所"})
      {:ok, incident} = Incidents.share_incident(admin, incident, true)

      {:ok, _lv, html} = live(conn, ~p"/incidents/#{incident}")

      assert html =~ "他拠点の場所"
      assert html =~ "（非公開）"
      refute html =~ other_manager.user.name
    end

    test "報告直後は編集でき、分析が始まると編集できない", %{
      conn: conn,
      member_scope: member,
      manager_scope: manager,
      vehicle: vehicle
    } do
      incident = incident_fixture(member, vehicle)

      {:ok, _lv, html} = live(conn, ~p"/incidents/#{incident}")
      assert html =~ "編集"

      {:ok, incident} = Incidents.start_analysis(manager, incident)

      {:ok, _lv, html} = live(conn, ~p"/incidents/#{incident}")
      refute html =~ ~p"/incidents/#{incident}/edit"
    end

    test "添付を削除できる", %{conn: conn, member_scope: member, vehicle: vehicle} do
      incident = incident_fixture(member, vehicle)

      attachment =
        CoreApp.AttachmentsFixtures.attachment_fixture(member, {:incident, incident.id})

      {:ok, lv, _html} = live(conn, ~p"/incidents/#{incident}/edit")

      html =
        lv
        |> element("button[phx-value-id='#{attachment.id}']")
        |> render_click()

      assert html =~ "添付ファイルを削除しました"
      assert Attachments.all_attachments_for(:incident, incident.id) == []
    end
  end
end
