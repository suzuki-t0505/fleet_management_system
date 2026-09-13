defmodule CoreAppWeb.OfficeLive.AdminTest do
  use CoreAppWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import CoreApp.AccountsFixtures
  import CoreApp.OfficesFixtures

  alias CoreApp.Offices

  setup %{conn: conn} do
    office = office_fixture(%{"code" => "HQ", "name" => "本社"})
    admin = admin_fixture(%{office_id: office.id})

    %{conn: log_in_user(conn, admin), admin: admin, office: office}
  end

  describe "一覧" do
    test "拠点が表示される", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/management/offices")

      assert html =~ "HQ"
    end

    test "無効な拠点は既定で表示されず、状態で絞り込める", %{conn: conn} do
      office_fixture(%{"code" => "OLD", "name" => "旧営業所", "active" => false})

      {:ok, lv, html} = live(conn, ~p"/management/offices")
      refute html =~ "旧営業所"

      html = lv |> form("#search-bar", %{"active" => "all"}) |> render_change()
      assert html =~ "旧営業所"
    end

    test "キーワードで絞り込める", %{conn: conn} do
      office_fixture(%{"code" => "OSK", "name" => "大阪営業所"})

      {:ok, lv, _html} = live(conn, ~p"/management/offices")

      html = lv |> form("#search-bar", %{"q" => "大阪"}) |> render_change()

      assert html =~ "OSK"

      # 拠点コードは一覧にしか出ないため、絞り込みの結果を確かめられる
      refute html =~ "HQ"
    end
  end

  describe "登録・編集" do
    test "拠点を登録できる", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/management/offices/new")

      assert {:ok, _index_lv, html} =
               lv
               |> form("#office-form",
                 office: %{
                   "code" => "NGY",
                   "name" => "名古屋営業所",
                   "postal_code" => "450-0002",
                   "address" => "愛知県名古屋市中村区名駅1-1-1",
                   "phone" => "052-000-0000"
                 }
               )
               |> render_submit()
               |> follow_redirect(conn)

      assert html =~ "拠点を登録しました"
      assert html =~ "名古屋営業所"
    end

    test "重複する拠点コードはエラーになる", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/management/offices/new")

      html =
        lv
        |> form("#office-form", office: %{"code" => "HQ", "name" => "重複営業所"})
        |> render_submit()

      assert html =~ "has already been taken"
    end

    test "無効化すると他機能の選択肢から外れる", %{conn: conn, office: office} do
      {:ok, lv, _html} = live(conn, ~p"/management/offices/#{office}/edit")

      assert {:ok, _index_lv, _html} =
               lv
               |> form("#office-form", office: %{"active" => "false"})
               |> render_submit()
               |> follow_redirect(conn)

      assert Offices.all_offices() == []
    end
  end

  describe "アクセス制御" do
    test "運行管理者は参照できない", %{conn: conn, office: office} do
      manager = manager_fixture(%{office_id: office.id})

      assert {:error, {:redirect, %{to: "/", flash: flash}}} =
               conn |> log_in_user(manager) |> live(~p"/management/offices")

      assert flash["error"] == "このページを表示する権限がありません"
    end

    test "一般利用者は参照できない", %{conn: conn, office: office} do
      member = user_fixture(%{office_id: office.id})

      assert {:error, {:redirect, %{to: "/"}}} =
               conn |> log_in_user(member) |> live(~p"/management/offices/new")
    end
  end
end
