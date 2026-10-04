defmodule CoreAppWeb.DispatchExportTest do
  use CoreAppWeb.ConnCase, async: true

  import CoreApp.AccountsFixtures
  import CoreApp.DispatchesFixtures
  import CoreApp.OfficesFixtures

  alias CoreApp.Accounts.Scope

  setup %{conn: conn} do
    office = office_fixture(%{"name" => "A営業所"})
    other_office = office_fixture(%{"name" => "B営業所"})

    manager = manager_fixture(%{office_id: office.id})
    scope = Scope.for_user(manager)

    %{
      conn: log_in_user(conn, manager),
      scope: scope,
      office: office,
      other_office: other_office
    }
  end

  test "配車のCSVをBOM付き・CRLF・日本語ヘッダーで出力する", %{conn: conn, scope: scope} do
    dispatch_fixture(scope, %{
      "title" => "朝便ルートA",
      "course_fare_yen" => "30000",
      "toll_yen" => "1500",
      "deliveries" => %{"0" => %{"destination" => "東京センター"}}
    })

    conn = get(conn, ~p"/management/exports/dispatches")
    body = response(conn, 200)

    assert get_resp_header(conn, "content-type") == ["text/csv; charset=utf-8"]
    assert String.starts_with?(body, "﻿配送開始日時,")
    assert body =~ "\r\n"
    assert body =~ "朝便ルートA"
    assert body =~ "コース一括"
    assert body =~ "東京センター"
    # 受取金額合計 = コース料金 + 高速料金
    assert body =~ "31500"

    assert [disposition] = get_resp_header(conn, "content-disposition")
    assert disposition =~ URI.encode("配車一覧")
  end

  test "配送ごとの配車は配送料金の合計と受取金額を出力する", %{conn: conn, scope: scope} do
    dispatch_fixture(scope, %{
      "pricing_type" => "per_delivery",
      "toll_yen" => "500",
      "deliveries" => %{
        "0" => %{"destination" => "東京", "fare_yen" => "10000"},
        "1" => %{"destination" => "横浜", "fare_yen" => "8000"}
      }
    })

    body = conn |> get(~p"/management/exports/dispatches") |> response(200)

    assert body =~ "配送ごと"
    assert body =~ "東京、横浜"
    assert body =~ ",18000,500,18500,"
  end

  test "画面の絞り込み条件が反映される", %{conn: conn, scope: scope} do
    dispatch_fixture(scope, %{"title" => "朝便"})
    dispatch_fixture(scope, %{"title" => "夜便"})

    body = conn |> get(~p"/management/exports/dispatches?#{%{"q" => "朝便"}}") |> response(200)

    assert body =~ "朝便"
    refute body =~ "夜便"
  end

  test "他拠点の行は出力されない", %{conn: conn, other_office: other_office} do
    other = manager_fixture(%{office_id: other_office.id}) |> Scope.for_user()
    dispatch_fixture(other, %{"title" => "他拠点便"})

    body = conn |> get(~p"/management/exports/dispatches") |> response(200)

    refute body =~ "他拠点便"
  end

  test "一般利用者は出力できない", %{conn: conn, office: office} do
    member = user_fixture(%{office_id: office.id})

    conn = conn |> log_in_user(member) |> get(~p"/management/exports/dispatches")

    assert redirected_to(conn) == "/"
  end

  test "配車売上集計のCSVを出力する", %{conn: conn, scope: scope} do
    dispatch_fixture(scope, %{"course_fare_yen" => "10000", "toll_yen" => "500"})

    body =
      conn
      |> get(
        ~p"/management/exports/reports/dispatch_revenue?#{%{"from" => "2026-10", "to" => "2026-10"}}"
      )
      |> response(200)

    assert String.starts_with?(body, "﻿月,対象,配車件数,運賃(円),高速料金(円),売上合計(円)")
    assert body =~ "2026/10"
    assert body =~ ",1,10000,500,10500"
  end
end
