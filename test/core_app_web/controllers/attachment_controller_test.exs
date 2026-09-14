defmodule CoreAppWeb.AttachmentControllerTest do
  use CoreAppWeb.ConnCase, async: true

  import CoreApp.AccountsFixtures
  import CoreApp.AttachmentsFixtures
  import CoreApp.IncidentsFixtures
  import CoreApp.OfficesFixtures
  import CoreApp.VehiclesFixtures

  alias CoreApp.Accounts.Scope
  alias CoreApp.Incidents

  setup %{conn: conn} do
    office_a = office_fixture(%{"name" => "A営業所"})
    office_b = office_fixture(%{"name" => "B営業所"})

    manager = manager_fixture(%{office_id: office_a.id})
    scope = Scope.for_user(manager)
    vehicle = vehicle_fixture(scope)
    incident = incident_fixture(scope, vehicle)
    attachment = attachment_fixture(scope, {:incident, incident.id}, %{filename: "現場写真.png"})

    %{
      conn: log_in_user(conn, manager),
      scope: scope,
      office_a: office_a,
      office_b: office_b,
      incident: incident,
      attachment: attachment
    }
  end

  test "参照できる利用者はダウンロードできる", %{conn: conn, attachment: attachment} do
    conn = get(conn, ~p"/attachments/#{attachment}")

    assert response(conn, 200) =~ "dummy image"
    assert get_resp_header(conn, "content-type") == ["image/png; charset=utf-8"]
    assert ["private, no-store"] = get_resp_header(conn, "cache-control")

    assert get_resp_header(conn, "content-disposition") == [
             "inline; filename*=UTF-8''#{URI.encode("現場写真.png")}"
           ]
  end

  test "他拠点の利用者はダウンロードできない", %{conn: conn, office_b: office_b} = ctx do
    other = manager_fixture(%{office_id: office_b.id})

    assert_raise Ecto.NoResultsError, fn ->
      conn |> log_in_user(other) |> get(~p"/attachments/#{ctx.attachment}")
    end
  end

  test "全社共有されると他拠点の利用者もダウンロードできる", %{conn: conn} = ctx do
    admin = admin_fixture(%{office_id: ctx.office_a.id}) |> Scope.for_user()
    {:ok, _shared} = Incidents.share_incident(admin, ctx.incident, true)

    other = manager_fixture(%{office_id: ctx.office_b.id})

    conn = conn |> log_in_user(other) |> get(~p"/attachments/#{ctx.attachment}")

    assert response(conn, 200) =~ "dummy image"
  end

  test "未ログインの利用者はログイン画面へ送られる", %{attachment: attachment} do
    conn = get(build_conn(), ~p"/attachments/#{attachment}")

    assert redirected_to(conn) == ~p"/users/log-in"
  end
end
