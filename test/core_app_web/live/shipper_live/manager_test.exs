defmodule CoreAppWeb.ShipperLive.ManagerTest do
  use CoreAppWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import CoreApp.AccountsFixtures
  import CoreApp.OfficesFixtures
  import CoreApp.ShippersFixtures

  alias CoreApp.Accounts.Scope
  alias CoreApp.Shippers

  setup %{conn: conn} do
    office_a = office_fixture(%{"name" => "A営業所"})
    office_b = office_fixture(%{"name" => "B営業所"})

    manager = manager_fixture(%{office_id: office_a.id})

    %{
      conn: log_in_user(conn, manager),
      manager_scope: Scope.for_user(manager),
      office_a: office_a,
      office_b: office_b
    }
  end

  describe "一覧" do
    test "自拠点の荷主だけが表示される", %{conn: conn, manager_scope: scope, office_b: office_b} do
      mine = shipper_fixture(scope, %{"name" => "自拠点荷主"})
      other_scope = Scope.for_user(manager_fixture(%{office_id: office_b.id}))
      other = shipper_fixture(other_scope, %{"name" => "他拠点荷主"})

      {:ok, _lv, html} = live(conn, ~p"/management/shippers")

      assert html =~ mine.name
      refute html =~ other.name
    end

    test "荷主が無いときは空状態を表示する", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/management/shippers")

      assert html =~ "条件に一致する荷主がありません"
    end
  end

  describe "登録" do
    test "荷主を登録できる", %{conn: conn, manager_scope: scope} do
      {:ok, lv, _html} = live(conn, ~p"/management/shippers/new")

      {:ok, _lv, html} =
        lv
        |> form("#shipper-form", shipper: %{name: "新規荷主", code: "N01", status: "active"})
        |> render_submit()
        |> follow_redirect(conn)

      assert html =~ "荷主を登録しました"
      assert html =~ "新規荷主"
      assert [%{name: "新規荷主"}] = Shippers.list_shippers(scope).entries
    end

    test "荷主名が空だとエラーを表示して保存しない", %{conn: conn, manager_scope: scope} do
      {:ok, lv, _html} = live(conn, ~p"/management/shippers/new")

      html =
        lv
        |> form("#shipper-form", shipper: %{name: ""})
        |> render_submit()

      assert html =~ "can&#39;t be blank"
      assert Shippers.list_shippers(scope).entries == []
    end
  end

  describe "編集" do
    test "荷主を無効化できる", %{conn: conn, manager_scope: scope} do
      shipper = shipper_fixture(scope)

      {:ok, lv, _html} = live(conn, ~p"/management/shippers/#{shipper}/edit")

      {:ok, _lv, html} =
        lv
        |> form("#shipper-form", shipper: %{status: "inactive"})
        |> render_submit()
        |> follow_redirect(conn)

      assert html =~ "荷主を更新しました"
      assert Shippers.get_shipper!(scope, shipper.id).status == :inactive
    end

    test "他拠点の荷主は参照できない", %{conn: conn, office_b: office_b} do
      other_scope = Scope.for_user(manager_fixture(%{office_id: office_b.id}))
      other = shipper_fixture(other_scope)

      assert_raise Ecto.NoResultsError, fn -> live(conn, ~p"/management/shippers/#{other}") end
    end
  end

  describe "権限" do
    test "一般利用者は荷主画面に入れない", %{conn: conn, office_a: office} do
      member = user_fixture(%{office_id: office.id})

      assert {:error, {:redirect, %{to: "/"}}} =
               conn |> log_in_user(member) |> live(~p"/management/shippers")
    end
  end
end
