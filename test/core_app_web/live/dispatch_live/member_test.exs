defmodule CoreAppWeb.DispatchLive.MemberTest do
  use CoreAppWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import CoreApp.AccountsFixtures
  import CoreApp.DispatchesFixtures
  import CoreApp.DriversFixtures
  import CoreApp.OfficesFixtures

  alias CoreApp.Accounts.Scope

  setup %{conn: conn} do
    office = office_fixture(%{"name" => "A営業所"})
    manager_scope = manager_fixture(%{office_id: office.id}) |> Scope.for_user()

    member = user_fixture(%{office_id: office.id})
    driver = driver_fixture(manager_scope, %{"user_id" => member.id, "name" => "自分 太郎"})

    %{
      conn: log_in_user(conn, member),
      manager_scope: manager_scope,
      driver: driver
    }
  end

  describe "一覧" do
    test "自分に割り当てられた配車だけが表示される", %{conn: conn, manager_scope: scope, driver: driver} do
      mine = dispatch_fixture(scope, %{"title" => "自分の配送", "driver_id" => driver.id})
      other = dispatch_fixture(scope, %{"title" => "他人の配送"})

      {:ok, _lv, html} = live(conn, ~p"/dispatches")

      assert html =~ mine.title
      refute html =~ other.title
    end

    test "配車が無いときは空状態を表示する", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/dispatches")

      assert html =~ "あなたに割り当てられた配車はありません"
    end
  end

  describe "詳細" do
    test "自分の配車は閲覧でき、受取金額は表示されない", %{conn: conn, manager_scope: scope, driver: driver} do
      dispatch =
        dispatch_fixture(scope, %{
          "driver_id" => driver.id,
          "deliveries" => %{"0" => %{"destination" => "東京センター"}}
        })

      {:ok, _lv, html} = live(conn, ~p"/dispatches/#{dispatch}")

      assert html =~ dispatch.title
      assert html =~ "東京センター"
      refute html =~ "受取金額"
      refute html =~ "31,500"
      refute html =~ "30,000"
    end

    test "他人の配車は参照できない", %{conn: conn, manager_scope: scope} do
      other = dispatch_fixture(scope)

      assert_raise Ecto.NoResultsError, fn -> live(conn, ~p"/dispatches/#{other}") end
    end
  end

  describe "権限" do
    test "管理画面（登録・編集）には入れない", %{conn: conn, manager_scope: scope, driver: driver} do
      dispatch = dispatch_fixture(scope, %{"driver_id" => driver.id})

      for path <- [
            ~p"/management/dispatches",
            ~p"/management/dispatches/new",
            ~p"/management/dispatches/#{dispatch}/edit"
          ] do
        assert {:error, {:redirect, %{to: "/"}}} = live(conn, path)
      end
    end
  end
end
