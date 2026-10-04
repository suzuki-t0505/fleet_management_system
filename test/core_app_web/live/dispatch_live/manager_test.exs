defmodule CoreAppWeb.DispatchLive.ManagerTest do
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
    office_a = office_fixture(%{"name" => "A営業所"})
    office_b = office_fixture(%{"name" => "B営業所"})

    manager = manager_fixture(%{office_id: office_a.id})
    scope = Scope.for_user(manager)

    %{
      conn: log_in_user(conn, manager),
      manager_scope: scope,
      office_a: office_a,
      office_b: office_b,
      shipper: shipper_fixture(scope, %{"name" => "北海道物流"}),
      vehicle: vehicle_fixture(scope, %{"plate_number" => "品川100あ1234"}),
      driver: driver_fixture(scope, %{"name" => "運転 太郎"})
    }
  end

  defp valid_form_params(%{shipper: shipper, vehicle: vehicle, driver: driver}, extra \\ %{}) do
    Map.merge(
      %{
        title: "朝便ルートA",
        started_at: "2026-10-01T09:00",
        ended_at: "2026-10-01T12:00",
        shipper_id: shipper.id,
        vehicle_id: vehicle.id,
        driver_id: driver.id,
        course_fare_yen: "30000",
        toll_yen: "1500"
      },
      extra
    )
  end

  describe "一覧" do
    test "自拠点の配車だけが表示される", %{conn: conn, manager_scope: scope, office_b: office_b} do
      mine = dispatch_fixture(scope, %{"title" => "自拠点の配送"})
      other_scope = Scope.for_user(manager_fixture(%{office_id: office_b.id}))
      other = dispatch_fixture(other_scope, %{"title" => "他拠点の配送"})

      {:ok, _lv, html} = live(conn, ~p"/management/dispatches")

      assert html =~ mine.title
      refute html =~ other.title
    end

    test "コース一括と配送ごとの受取金額が表示される", %{conn: conn, manager_scope: scope} do
      dispatch_fixture(scope, %{
        "title" => "コース便",
        "course_fare_yen" => "30000",
        "toll_yen" => "1500"
      })

      dispatch_fixture(scope, %{
        "title" => "配送ごと便",
        "pricing_type" => "per_delivery",
        "toll_yen" => "500",
        "deliveries" => %{
          "0" => %{"destination" => "東京", "fare_yen" => "10000"},
          "1" => %{"destination" => "横浜", "fare_yen" => "8000"}
        }
      })

      {:ok, _lv, html} = live(conn, ~p"/management/dispatches")

      assert html =~ "31,500 円"
      assert html =~ "18,500 円"
      assert html =~ "コース一括"
      assert html =~ "配送ごと"
    end

    test "配車が無いときは空状態を表示する", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/management/dispatches")

      assert html =~ "条件に一致する配車がありません"
    end

    test "キーワードで絞り込める", %{conn: conn, manager_scope: scope} do
      dispatch_fixture(scope, %{"title" => "朝便ルート"})
      dispatch_fixture(scope, %{"title" => "夜便ルート"})

      {:ok, lv, _html} = live(conn, ~p"/management/dispatches")

      html = lv |> form("#search-bar", %{q: "朝便"}) |> render_change()

      assert html =~ "朝便ルート"
      refute html =~ "夜便ルート"
    end
  end

  describe "登録" do
    test "コース一括の配車を登録できる", %{conn: conn, manager_scope: scope} = ctx do
      {:ok, lv, _html} = live(conn, ~p"/management/dispatches/new")

      {:ok, _lv, html} =
        lv
        |> form("#dispatch-form", dispatch: valid_form_params(ctx))
        |> render_submit()
        |> follow_redirect(conn)

      assert html =~ "配車を登録しました"
      assert html =~ "朝便ルートA"
      assert html =~ "31,500 円"

      assert [dispatch] = Dispatches.list_dispatches(scope).entries
      assert dispatch.pricing_type == :course_total
      assert dispatch.course_fare_yen == 30_000
      assert dispatch.toll_yen == 1_500
      # フォームの日時はJSTとして保存される
      assert dispatch.started_at == ~U[2026-10-01 00:00:00Z]
    end

    test "料金方式を切り替えると入力欄が切り替わる", %{conn: conn} = ctx do
      {:ok, lv, _html} = live(conn, ~p"/management/dispatches/new")

      assert has_element?(lv, "input[name='dispatch[course_fare_yen]']")

      lv
      |> form("#dispatch-form", dispatch: valid_form_params(ctx, %{pricing_type: "per_delivery"}))
      |> render_change()

      refute has_element?(lv, "input[name='dispatch[course_fare_yen]']")

      lv
      |> form("#dispatch-form", dispatch: %{deliveries_sort: ["new"]})
      |> render_change()

      assert has_element?(lv, "input[name='dispatch[deliveries][0][fare_yen]']")
    end

    test "配送ごとの配車を明細つきで登録できる", %{conn: conn, manager_scope: scope} = ctx do
      {:ok, lv, _html} = live(conn, ~p"/management/dispatches/new")

      lv
      |> form("#dispatch-form", dispatch: valid_form_params(ctx, %{pricing_type: "per_delivery"}))
      |> render_change()

      lv |> form("#dispatch-form", dispatch: %{deliveries_sort: ["new"]}) |> render_change()
      lv |> form("#dispatch-form", dispatch: %{deliveries_sort: ["0", "new"]}) |> render_change()

      {:ok, _lv, html} =
        lv
        |> form("#dispatch-form",
          dispatch: %{
            deliveries: %{
              "0" => %{destination: "東京センター", fare_yen: "10000"},
              "1" => %{destination: "横浜センター", fare_yen: "8000"}
            }
          }
        )
        |> render_submit()
        |> follow_redirect(conn)

      assert html =~ "東京センター"
      assert html =~ "横浜センター"
      assert html =~ "19,500 円"

      assert [dispatch] = Dispatches.list_dispatches(scope).entries
      assert dispatch.course_fare_yen == nil
      assert Enum.map(dispatch.deliveries, & &1.destination) == ["東京センター", "横浜センター"]
    end

    test "入力内容から受取金額の合計をプレビューする", %{conn: conn} = ctx do
      {:ok, lv, _html} = live(conn, ~p"/management/dispatches/new")

      lv |> form("#dispatch-form", dispatch: valid_form_params(ctx)) |> render_change()

      assert lv |> element("#dispatch-total-preview") |> render() =~ "31,500 円"
    end

    test "終了日時が開始日時以前だとエラーを表示して保存しない", %{conn: conn, manager_scope: scope} = ctx do
      {:ok, lv, _html} = live(conn, ~p"/management/dispatches/new")

      html =
        lv
        |> form("#dispatch-form",
          dispatch: valid_form_params(ctx, %{ended_at: "2026-10-01T09:00"})
        )
        |> render_submit()

      assert html =~ "配送開始日時より後の日時を入力してください"
      assert Dispatches.list_dispatches(scope).entries == []
    end

    test "必須項目が空だとエラーを表示して保存しない", %{conn: conn, manager_scope: scope} do
      {:ok, lv, _html} = live(conn, ~p"/management/dispatches/new")

      html = lv |> form("#dispatch-form", dispatch: %{title: ""}) |> render_submit()

      assert html =~ "can&#39;t be blank"
      assert Dispatches.list_dispatches(scope).entries == []
    end

    test "配送ごとで明細が無いとエラーを表示する", %{conn: conn} = ctx do
      {:ok, lv, _html} = live(conn, ~p"/management/dispatches/new")

      html =
        lv
        |> form("#dispatch-form",
          dispatch: valid_form_params(ctx, %{pricing_type: "per_delivery"})
        )
        |> render_submit()

      assert html =~ "を1件以上入力してください"
    end

    test "同じ車両の時間が重なると警告を表示するが、保存はできる",
         %{conn: conn, manager_scope: scope, vehicle: vehicle} = ctx do
      dispatch_fixture(scope, %{
        "vehicle_id" => vehicle.id,
        "started_at" => "2026-10-01T00:00:00Z",
        "ended_at" => "2026-10-01T03:00:00Z"
      })

      {:ok, lv, _html} = live(conn, ~p"/management/dispatches/new")

      html = lv |> form("#dispatch-form", dispatch: valid_form_params(ctx)) |> render_change()
      assert html =~ "同じ車両で時間帯が重なる配車が既に登録されています"

      {:ok, _lv, html} =
        lv
        |> form("#dispatch-form", dispatch: valid_form_params(ctx))
        |> render_submit()
        |> follow_redirect(conn)

      assert html =~ "配車を登録しました"
      assert length(Dispatches.list_dispatches(scope).entries) == 2
    end

    test "無効な荷主は選択肢に出ない", %{conn: conn, manager_scope: scope} do
      shipper_fixture(scope, %{"name" => "停止中の荷主", "status" => "inactive"})

      {:ok, _lv, html} = live(conn, ~p"/management/dispatches/new")

      refute html =~ "停止中の荷主"
      assert html =~ "北海道物流"
    end
  end

  describe "編集" do
    test "配車を更新でき、料金方式も切り替えられる", %{conn: conn, manager_scope: scope} = ctx do
      dispatch = dispatch_fixture(scope, %{"title" => "変更前"})

      {:ok, lv, _html} = live(conn, ~p"/management/dispatches/#{dispatch}/edit")

      lv
      |> form("#dispatch-form", dispatch: %{pricing_type: "per_delivery"})
      |> render_change()

      lv |> form("#dispatch-form", dispatch: %{deliveries_sort: ["new"]}) |> render_change()

      {:ok, _lv, html} =
        lv
        |> form("#dispatch-form",
          dispatch: %{
            title: "変更後",
            shipper_id: ctx.shipper.id,
            deliveries: %{"0" => %{destination: "大阪", fare_yen: "12000"}}
          }
        )
        |> render_submit()
        |> follow_redirect(conn)

      assert html =~ "配車を更新しました"
      assert html =~ "変更後"

      updated = Dispatches.get_dispatch!(scope, dispatch.id)
      assert updated.pricing_type == :per_delivery
      assert updated.course_fare_yen == nil
      assert Dispatches.total_amount_yen(updated) == 13_500
    end

    test "他拠点の配車は参照できない", %{conn: conn, office_b: office_b} do
      other_scope = Scope.for_user(manager_fixture(%{office_id: office_b.id}))
      other = dispatch_fixture(other_scope)

      assert_raise Ecto.NoResultsError, fn -> live(conn, ~p"/management/dispatches/#{other}") end

      assert_raise Ecto.NoResultsError, fn ->
        live(conn, ~p"/management/dispatches/#{other}/edit")
      end
    end
  end

  describe "詳細" do
    test "料金内訳と配送先が表示される", %{conn: conn, manager_scope: scope} do
      dispatch =
        dispatch_fixture(scope, %{
          "pricing_type" => "per_delivery",
          "toll_yen" => "500",
          "deliveries" => %{
            "0" => %{"destination" => "東京センター", "fare_yen" => "10000"},
            "1" => %{"destination" => "横浜センター", "fare_yen" => "8000"}
          }
        })

      {:ok, _lv, html} = live(conn, ~p"/management/dispatches/#{dispatch}")

      assert html =~ "東京センター"
      assert html =~ "10,000 円"
      assert html =~ "高速料金"
      assert html =~ "18,500 円"
    end
  end

  describe "権限" do
    test "一般利用者は管理画面に入れない", %{conn: conn, office_a: office} do
      member = user_fixture(%{office_id: office.id})

      assert {:error, {:redirect, %{to: "/"}}} =
               conn |> log_in_user(member) |> live(~p"/management/dispatches")
    end
  end
end
