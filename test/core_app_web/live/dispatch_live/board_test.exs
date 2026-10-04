defmodule CoreAppWeb.DispatchLive.BoardTest do
  use CoreAppWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import CoreApp.AccountsFixtures
  import CoreApp.DispatchesFixtures
  import CoreApp.DriversFixtures
  import CoreApp.OfficesFixtures
  import CoreApp.ShippersFixtures
  import CoreApp.VehiclesFixtures

  alias CoreApp.Accounts.Scope

  @date "2026-10-01"
  @path "/management/dispatches/board"

  setup %{conn: conn} do
    office_a = office_fixture(%{"name" => "A営業所"})
    office_b = office_fixture(%{"name" => "B営業所"})

    manager = manager_fixture(%{office_id: office_a.id})
    scope = Scope.for_user(manager)

    %{
      conn: log_in_user(conn, manager),
      scope: scope,
      office_a: office_a,
      office_b: office_b,
      vehicle: vehicle_fixture(scope, %{"plate_number" => "品川100あ1111"}),
      driver: driver_fixture(scope, %{"name" => "運転 太郎"})
    }
  end

  defp dispatch_on(scope, ctx, from, to, attrs \\ %{}) do
    dispatch_fixture(
      scope,
      Map.merge(
        %{
          "vehicle_id" => ctx.vehicle.id,
          "driver_id" => ctx.driver.id,
          "started_at" => from,
          "ended_at" => to
        },
        attrs
      )
    )
  end

  describe "管理者向けの配車表" do
    test "その日の配車がバーで表示され、詳細へのリンクになる", %{conn: conn, scope: scope} = ctx do
      dispatch =
        dispatch_on(scope, ctx, "2026-10-01T09:00", "2026-10-01T15:00", %{"title" => "朝便"})

      {:ok, lv, html} = live(conn, "#{@path}?date=#{@date}")

      assert html =~ "2026年10月1日（木）"
      assert has_element?(lv, "#board-bar-#{dispatch.id}", "朝便")
      assert has_element?(lv, "#board-bar-#{dispatch.id}", "9:00-15:00")

      assert lv |> element("#board-bar-#{dispatch.id}") |> render() =~
               "/management/dispatches/#{dispatch.id}"

      # 9:00〜15:00 は 0:00〜24:00 に対して left 37.5%・width 25%
      assert render(element(lv, "#board-bar-#{dispatch.id}")) =~ "left: 37.5%; width: 25.0%"
    end

    test "配車の無い車両の行も表示する（空きが分かる）", %{conn: conn} = ctx do
      empty = vehicle_fixture(ctx.scope, %{"plate_number" => "空き車両9999"})

      {:ok, lv, _html} = live(conn, "#{@path}?date=#{@date}")

      assert has_element?(lv, "#board-row-#{empty.id}", "空き車両9999")
      assert has_element?(lv, "#board-row-#{ctx.vehicle.id}", "品川100あ1111")
    end

    test "その日の配車が無くても行と凡例は壊れない", %{conn: conn} do
      {:ok, lv, _html} = live(conn, "#{@path}?date=#{@date}")

      assert has_element?(lv, "#dispatch-board")
      refute has_element?(lv, "[id^='board-bar-']")
    end

    test "別の日の配車は表示しない", %{conn: conn, scope: scope} = ctx do
      other = dispatch_on(scope, ctx, "2026-10-02T09:00", "2026-10-02T12:00")

      {:ok, lv, _html} = live(conn, "#{@path}?date=#{@date}")

      refute has_element?(lv, "#board-bar-#{other.id}")
    end

    test "時間が重なる配車は強調され、重ならない配車は強調されない", %{conn: conn, scope: scope} = ctx do
      a = dispatch_on(scope, ctx, "2026-10-01T08:00", "2026-10-01T12:00")
      b = dispatch_on(scope, ctx, "2026-10-01T10:00", "2026-10-01T14:00")
      c = dispatch_on(scope, ctx, "2026-10-01T16:00", "2026-10-01T18:00")

      {:ok, lv, _html} = live(conn, "#{@path}?date=#{@date}")

      assert lv |> element("#board-bar-#{a.id}") |> render() =~ "border-accent-orange"
      assert lv |> element("#board-bar-#{b.id}") |> render() =~ "border-accent-orange"
      refute lv |> element("#board-bar-#{c.id}") |> render() =~ "border-accent-orange"
      # 重なる2件は上下にずらして表示する
      assert render(element(lv, "#board-bar-#{a.id}")) =~ "top: 4px"
      assert render(element(lv, "#board-bar-#{b.id}")) =~ "top: 48px"
    end

    test "日付をまたぐ配車は続きが分かるように表示する", %{conn: conn, scope: scope} = ctx do
      from_prev = dispatch_on(scope, ctx, "2026-09-30T22:00", "2026-10-01T03:00")
      to_next = dispatch_on(scope, ctx, "2026-10-01T21:00", "2026-10-02T06:00")

      {:ok, lv, _html} = live(conn, "#{@path}?date=#{@date}")

      assert has_element?(lv, "#board-bar-#{from_prev.id} [aria-label='前日から続く']")
      refute has_element?(lv, "#board-bar-#{from_prev.id} [aria-label='翌日へ続く']")
      assert has_element?(lv, "#board-bar-#{to_next.id} [aria-label='翌日へ続く']")
    end

    test "荷積み・荷降ろしの印を重ねて表示する", %{conn: conn, scope: scope} = ctx do
      dispatch =
        dispatch_on(scope, ctx, "2026-10-01T09:00", "2026-10-01T15:00", %{
          "deliveries" => %{
            "0" => %{
              "destination" => "東京センター",
              "loading_at" => "2026-10-01T10:00",
              "unloading_at" => "2026-10-01T13:00"
            }
          }
        })

      {:ok, lv, _html} = live(conn, "#{@path}?date=#{@date}")

      assert has_element?(lv, "#board-bar-#{dispatch.id} span[title*='荷積み 東京センター']", "▲")
      assert has_element?(lv, "#board-bar-#{dispatch.id} span[title*='荷降ろし 東京センター']", "▼")
    end

    test "荷主の色を凡例に出す", %{conn: conn, scope: scope} = ctx do
      shipper = shipper_fixture(scope, %{"name" => "凡例テスト荷主"})

      dispatch_on(scope, ctx, "2026-10-01T09:00", "2026-10-01T12:00", %{
        "shipper_id" => shipper.id
      })

      {:ok, lv, _html} = live(conn, "#{@path}?date=#{@date}")

      assert has_element?(lv, "#board-legend", "凡例テスト荷主")
    end

    test "ドライバー軸に切り替えられる", %{conn: conn, scope: scope} = ctx do
      dispatch_on(scope, ctx, "2026-10-01T09:00", "2026-10-01T12:00")
      idle = driver_fixture(scope, %{"name" => "待機 花子"})

      {:ok, lv, _html} = live(conn, "#{@path}?date=#{@date}")

      lv |> form("#board-filter", %{date: @date, axis: "driver"}) |> render_change()
      assert_patch(lv, "#{@path}?axis=driver&date=#{@date}")

      assert has_element?(lv, "#board-row-#{ctx.driver.id}", "運転 太郎")
      assert has_element?(lv, "#board-row-#{idle.id}", "待機 花子")
      refute has_element?(lv, "#board-row-#{ctx.vehicle.id}")
    end

    test "前日・翌日・日付指定で移動でき、URLで状態が再現できる", %{conn: conn, scope: scope} = ctx do
      next_day = dispatch_on(scope, ctx, "2026-10-02T09:00", "2026-10-02T12:00")

      {:ok, lv, _html} = live(conn, "#{@path}?date=#{@date}")
      refute has_element?(lv, "#board-bar-#{next_day.id}")

      lv |> element("#board-next") |> render_click()
      assert_patch(lv, "#{@path}?axis=vehicle&date=2026-10-02")
      assert has_element?(lv, "#board-bar-#{next_day.id}")

      lv |> element("#board-prev") |> render_click()
      assert_patch(lv, "#{@path}?axis=vehicle&date=#{@date}")
      refute has_element?(lv, "#board-bar-#{next_day.id}")

      lv |> form("#board-filter", %{date: "2026-10-02"}) |> render_change()
      assert has_element?(lv, "#board-bar-#{next_day.id}")

      # 同じURLを直接開いても同じ画面になる
      {:ok, lv2, _html} = live(conn, "#{@path}?axis=vehicle&date=2026-10-02")
      assert has_element?(lv2, "#board-bar-#{next_day.id}")
    end

    test "不正な日付は今日を表示する", %{conn: conn} do
      today = CoreApp.Utils.ConvertDatetime.today()

      {:ok, _lv, html} = live(conn, "#{@path}?date=abc")

      assert html =~ "#{today.year}年#{today.month}月#{today.day}日"
    end

    test "他拠点の配車は表示されない", %{conn: conn, office_b: office_b} do
      other_scope = Scope.for_user(manager_fixture(%{office_id: office_b.id}))

      other =
        dispatch_fixture(other_scope, %{
          "title" => "他拠点便",
          "started_at" => "2026-10-01T09:00",
          "ended_at" => "2026-10-01T12:00"
        })

      {:ok, lv, html} = live(conn, "#{@path}?date=#{@date}")

      refute has_element?(lv, "#board-bar-#{other.id}")
      refute html =~ "他拠点便"
    end

    test "管理者は拠点で絞り込める", %{office_a: office_a, office_b: office_b, scope: scope} = ctx do
      admin = admin_fixture(%{office_id: office_a.id})
      other_scope = Scope.for_user(manager_fixture(%{office_id: office_b.id}))

      mine = dispatch_on(scope, ctx, "2026-10-01T09:00", "2026-10-01T12:00")

      other =
        dispatch_fixture(other_scope, %{
          "started_at" => "2026-10-01T09:00",
          "ended_at" => "2026-10-01T12:00"
        })

      {:ok, lv, _html} = live(log_in_user(build_conn(), admin), "#{@path}?date=#{@date}")
      assert has_element?(lv, "#board-bar-#{mine.id}")
      assert has_element?(lv, "#board-bar-#{other.id}")

      lv |> form("#board-filter", %{date: @date, office_id: office_b.id}) |> render_change()

      refute has_element?(lv, "#board-bar-#{mine.id}")
      assert has_element?(lv, "#board-bar-#{other.id}")
    end

    test "配車一覧と配車表をたがいに行き来できる", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/management/dispatches")

      assert has_element?(lv, "a[href='/management/dispatches/board']", "配車表")

      {:ok, lv, _html} = live(conn, "#{@path}?date=#{@date}")
      assert has_element?(lv, "a[href='/management/dispatches']", "配車一覧")
    end
  end

  describe "運転者向けの配車表" do
    setup %{scope: scope, office_a: office} do
      member = user_fixture(%{office_id: office.id})
      driver = driver_fixture(scope, %{"user_id" => member.id, "name" => "自分 次郎"})

      %{member: member, member_driver: driver}
    end

    test "自分の配車だけが表示され、詳細へのリンクになる", %{scope: scope, member: member} = ctx do
      mine =
        dispatch_on(scope, ctx, "2026-10-01T09:00", "2026-10-01T12:00", %{
          "driver_id" => ctx.member_driver.id
        })

      other = dispatch_on(scope, ctx, "2026-10-01T13:00", "2026-10-01T15:00")

      {:ok, lv, _html} =
        live(log_in_user(build_conn(), member), "/dispatches/board?date=#{@date}")

      assert has_element?(lv, "#board-bar-#{mine.id}")
      refute has_element?(lv, "#board-bar-#{other.id}")
      assert lv |> element("#board-bar-#{mine.id}") |> render() =~ "/dispatches/#{mine.id}"
    end

    test "日付を移動できる", %{scope: scope, member: member} = ctx do
      next_day =
        dispatch_on(scope, ctx, "2026-10-02T09:00", "2026-10-02T12:00", %{
          "driver_id" => ctx.member_driver.id
        })

      {:ok, lv, _html} =
        live(log_in_user(build_conn(), member), "/dispatches/board?date=#{@date}")

      lv |> element("#board-next") |> render_click()
      assert_patch(lv, "/dispatches/board?date=2026-10-02")
      assert has_element?(lv, "#board-bar-#{next_day.id}")
    end

    test "管理者向けの配車表には入れない", %{member: member} do
      assert {:error, {:redirect, %{to: "/"}}} =
               live(log_in_user(build_conn(), member), @path)
    end
  end
end
