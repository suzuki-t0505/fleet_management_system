defmodule CoreAppWeb.DispatchLive.DeliveryTimesTest do
  use CoreAppWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import CoreApp.AccountsFixtures
  import CoreApp.DispatchesFixtures
  import CoreApp.DriversFixtures
  import CoreApp.OfficesFixtures
  import CoreApp.ShippersFixtures
  import CoreApp.VehiclesFixtures

  alias CoreApp.Accounts.Scope
  alias CoreApp.Dispatches

  setup %{conn: conn} do
    office = office_fixture(%{"name" => "A営業所"})
    manager = manager_fixture(%{office_id: office.id})
    scope = Scope.for_user(manager)

    %{
      conn: log_in_user(conn, manager),
      scope: scope,
      office: office,
      shipper: shipper_fixture(scope, %{"name" => "北海道物流"}),
      vehicle: vehicle_fixture(scope, %{"plate_number" => "品川100あ1234"}),
      driver: driver_fixture(scope, %{"name" => "運転 太郎"})
    }
  end

  defp form_params(ctx, extra) do
    Map.merge(
      %{
        title: "朝便",
        started_at: "2026-10-01T09:00",
        ended_at: "2026-10-01T18:00",
        shipper_id: ctx.shipper.id,
        vehicle_id: ctx.vehicle.id,
        driver_id: ctx.driver.id,
        course_fare_yen: "30000"
      },
      extra
    )
  end

  test "配送先の荷積み・荷降ろし時刻を登録でき、詳細に表示される", %{conn: conn, scope: scope} = ctx do
    {:ok, lv, _html} = live(conn, ~p"/management/dispatches/new")

    lv |> form("#dispatch-form", dispatch: form_params(ctx, %{})) |> render_change()
    lv |> form("#dispatch-form", dispatch: %{deliveries_sort: ["new"]}) |> render_change()

    assert has_element?(lv, "input[name='dispatch[deliveries][0][loading_at]']")
    assert has_element?(lv, "input[name='dispatch[deliveries][0][unloading_at]']")

    {:ok, _lv, html} =
      lv
      |> form("#dispatch-form",
        dispatch: %{
          deliveries: %{
            "0" => %{
              destination: "東京センター",
              loading_at: "2026-10-01T10:00",
              unloading_at: "2026-10-01T11:30"
            }
          }
        }
      )
      |> render_submit()
      |> follow_redirect(conn)

    assert html =~ "東京センター"
    assert html =~ "2026/10/01 10:00"
    assert html =~ "2026/10/01 11:30"

    assert [%{deliveries: [d]}] = Dispatches.list_dispatches(scope).entries
    # JST 10:00 = UTC 01:00
    assert d.loading_at == ~U[2026-10-01 01:00:00Z]
  end

  test "範囲外の時刻はエラーを表示して保存しない", %{conn: conn, scope: scope} = ctx do
    {:ok, lv, _html} = live(conn, ~p"/management/dispatches/new")

    lv |> form("#dispatch-form", dispatch: form_params(ctx, %{})) |> render_change()
    lv |> form("#dispatch-form", dispatch: %{deliveries_sort: ["new"]}) |> render_change()

    html =
      lv
      |> form("#dispatch-form",
        dispatch: %{
          deliveries: %{
            "0" => %{destination: "東京", loading_at: "2026-10-01T08:00", unloading_at: ""}
          }
        }
      )
      |> render_submit()

    assert html =~ "は配送開始〜終了の間の日時を入力してください"
    assert Dispatches.list_dispatches(scope).entries == []
  end

  test "編集フォームに保存済みの時刻がJSTで表示される", %{conn: conn, scope: scope} do
    dispatch =
      dispatch_fixture(scope, %{
        "started_at" => "2026-10-01T09:00",
        "ended_at" => "2026-10-01T18:00",
        "deliveries" => %{
          "0" => %{"destination" => "東京", "loading_at" => "2026-10-01T10:15"}
        }
      })

    {:ok, lv, _html} = live(conn, ~p"/management/dispatches/#{dispatch}/edit")

    assert lv
           |> element("input[name='dispatch[deliveries][0][loading_at]']")
           |> render() =~ "2026-10-01T10:15"
  end

  test "運転者向けの詳細にも荷積み・荷降ろし時刻が表示される", %{conn: conn, scope: scope, office: office} do
    member = user_fixture(%{office_id: office.id})
    driver = driver_fixture(scope, %{"user_id" => member.id})

    dispatch =
      dispatch_fixture(scope, %{
        "driver_id" => driver.id,
        "started_at" => "2026-10-01T09:00",
        "ended_at" => "2026-10-01T18:00",
        "deliveries" => %{
          "0" => %{
            "destination" => "東京センター",
            "loading_at" => "2026-10-01T10:15",
            "unloading_at" => "2026-10-01T12:45"
          }
        }
      })

    {:ok, _lv, html} = conn |> log_in_user(member) |> live(~p"/dispatches/#{dispatch}")

    assert html =~ "東京センター"
    assert html =~ "2026/10/01 10:15"
    assert html =~ "2026/10/01 12:45"
  end
end
