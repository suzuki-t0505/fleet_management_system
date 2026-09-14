defmodule CoreAppWeb.DriverLive.ManagerTest do
  use CoreAppWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import CoreApp.AccountsFixtures
  import CoreApp.DriversFixtures
  import CoreApp.OfficesFixtures

  alias CoreApp.Accounts.Scope
  alias CoreApp.Drivers
  alias CoreApp.Utils.ConvertDatetime

  setup %{conn: conn} do
    office_a = office_fixture(%{"name" => "A営業所"})
    office_b = office_fixture(%{"name" => "B営業所"})

    manager = manager_fixture(%{office_id: office_a.id})
    admin = admin_fixture(%{office_id: office_a.id})

    %{
      conn: log_in_user(conn, manager),
      manager: manager,
      manager_scope: Scope.for_user(manager),
      manager_b_scope: Scope.for_user(manager_fixture(%{office_id: office_b.id})),
      admin: admin,
      office_a: office_a,
      office_b: office_b
    }
  end

  defp valid_form_attrs(attrs \\ %{}) do
    Enum.into(attrs, %{
      "code" => "D-9001",
      "name" => "登録 太郎",
      "name_kana" => "とうろく たろう",
      "employment_type" => "full_time",
      "hired_on" => "2022-04-01",
      "license_number" => "999900001",
      "license_types" => ["medium"],
      "license_expires_on" => "2029-12-31"
    })
  end

  describe "一覧" do
    test "自拠点の運転者のみ表示される", %{conn: conn, manager_scope: a, manager_b_scope: b} do
      mine = driver_fixture(a, %{"name" => "自拠点 太郎"})
      other = driver_fixture(b, %{"name" => "他拠点 次郎"})

      {:ok, _lv, html} = live(conn, ~p"/management/drivers")

      assert html =~ mine.name
      refute html =~ other.name
    end

    test "運転者がいないときは空状態を表示する", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/management/drivers")

      assert html =~ "条件に一致する運転者がいません"
    end

    test "キーワードで絞り込める", %{conn: conn, manager_scope: scope} do
      driver_fixture(scope, %{"name" => "検索 対象", "name_kana" => "けんさく たいしょう"})
      driver_fixture(scope, %{"name" => "対象外 花子", "name_kana" => "たいしょうがい はなこ"})

      {:ok, lv, _html} = live(conn, ~p"/management/drivers")

      html = lv |> form("#search-bar", %{"q" => "けんさく"}) |> render_change()

      assert html =~ "検索 対象"
      refute html =~ "対象外 花子"
    end

    test "退職者は既定で表示されない", %{conn: conn, manager_scope: scope} do
      driver = driver_fixture(scope, %{"name" => "退職 三郎"})

      {:ok, _} =
        Drivers.update_driver(scope, driver, %{
          "employment_type" => "retired",
          "retired_on" => "2026-08-31"
        })

      {:ok, lv, html} = live(conn, ~p"/management/drivers")
      refute html =~ "退職 三郎"

      html = lv |> form("#search-bar", %{"employment_type" => "retired"}) |> render_change()
      assert html =~ "退職 三郎"
    end

    test "拠点の絞り込みは管理者のみ表示される", %{conn: conn, admin: admin} do
      {:ok, _lv, manager_html} = live(conn, ~p"/management/drivers")
      refute manager_html =~ "filter-office_id"

      {:ok, _lv, admin_html} = conn |> log_in_user(admin) |> live(~p"/management/drivers")
      assert admin_html =~ "filter-office_id"
    end
  end

  describe "登録" do
    test "運転者を登録すると詳細に遷移し、一覧に表示される", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/management/drivers/new")

      assert {:ok, _show_lv, html} =
               lv
               |> form("#driver-form", driver: valid_form_attrs())
               |> render_submit()
               |> follow_redirect(conn)

      assert html =~ "運転者を登録しました"
      assert html =~ "登録 太郎"

      {:ok, _index_lv, index_html} = live(conn, ~p"/management/drivers")
      assert index_html =~ "登録 太郎"
    end

    test "運転者コードが重複するとエラーになる", %{conn: conn, manager_scope: scope} do
      driver_fixture(scope, %{"code" => "D-9001"})

      {:ok, lv, _html} = live(conn, ~p"/management/drivers/new")

      html = lv |> form("#driver-form", driver: valid_form_attrs()) |> render_submit()

      assert html =~ "この運転者コードは既に登録されています"
    end

    test "免許種類を選ばないとエラーになる", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/management/drivers/new")

      html =
        lv
        |> form("#driver-form", driver: valid_form_attrs(%{"license_types" => [""]}))
        |> render_submit()

      assert html =~ "を1つ以上選択してください"
    end

    test "免許証有効期限が過去日でも保存でき、警告が表示される", %{conn: conn} do
      past = ConvertDatetime.today() |> Date.add(-5) |> Date.to_iso8601()

      {:ok, lv, _html} = live(conn, ~p"/management/drivers/new")

      warning =
        lv
        |> form("#driver-form", driver: valid_form_attrs(%{"license_expires_on" => past}))
        |> render_change()

      assert warning =~ "免許証の有効期限が5日超過しています"

      assert {:ok, _show_lv, html} =
               lv
               |> form("#driver-form", driver: valid_form_attrs(%{"license_expires_on" => past}))
               |> render_submit()
               |> follow_redirect(conn)

      assert html =~ "運転者を登録しました"
      assert html =~ "運転業務に就かせる前に確認してください"
    end
  end

  describe "編集" do
    test "更新すると詳細に反映される", %{conn: conn, manager_scope: scope} do
      driver = driver_fixture(scope, %{"name" => "変更 前"})

      {:ok, lv, _html} = live(conn, ~p"/management/drivers/#{driver}/edit")

      assert {:ok, _show_lv, html} =
               lv
               |> form("#driver-form", driver: %{"name" => "変更 後"})
               |> render_submit()
               |> follow_redirect(conn)

      assert html =~ "運転者を更新しました"
      assert html =~ "変更 後"
    end

    test "退職にすると一覧から消える", %{conn: conn, manager_scope: scope} do
      driver = driver_fixture(scope, %{"name" => "退職 予定"})

      {:ok, lv, _html} = live(conn, ~p"/management/drivers/#{driver}/edit")

      assert {:ok, _show_lv, _html} =
               lv
               |> form("#driver-form",
                 driver: %{"employment_type" => "retired", "retired_on" => "2026-08-31"}
               )
               |> render_submit()
               |> follow_redirect(conn)

      {:ok, _index_lv, index_html} = live(conn, ~p"/management/drivers")
      refute index_html =~ "退職 予定"
    end
  end

  describe "アカウントの紐付け" do
    test "候補には自拠点の未紐付けアカウントのみ表示される", %{
      conn: conn,
      manager_scope: scope,
      office_a: office_a,
      office_b: office_b
    } do
      free = user_fixture(%{office_id: office_a.id, name: "未紐付け 花子"})
      linked = user_fixture(%{office_id: office_a.id, name: "紐付済み 次郎"})
      other_office = user_fixture(%{office_id: office_b.id, name: "他拠点 三郎"})
      driver_fixture(scope, %{"user_id" => linked.id})

      {:ok, _lv, html} = live(conn, ~p"/management/drivers/new")

      assert html =~ free.name
      refute html =~ linked.name
      refute html =~ other_office.name
    end

    test "紐付けたアカウントが詳細に表示される", %{conn: conn, office_a: office_a} do
      user = user_fixture(%{office_id: office_a.id, name: "紐付け 太郎"})

      {:ok, lv, _html} = live(conn, ~p"/management/drivers/new")

      assert {:ok, _show_lv, html} =
               lv
               |> form("#driver-form", driver: valid_form_attrs(%{"user_id" => user.id}))
               |> render_submit()
               |> follow_redirect(conn)

      assert html =~ user.email
    end
  end

  describe "詳細" do
    test "基本情報・免許情報・アカウントが表示される", %{conn: conn, manager_scope: scope} do
      driver = driver_fixture(scope)

      {:ok, _lv, html} = live(conn, ~p"/management/drivers/#{driver}")

      assert html =~ driver.name
      assert html =~ driver.license_number
      assert html =~ "アカウントは紐付いていません"
      assert html =~ "履歴"
    end
  end

  describe "スコープ境界と認可" do
    test "他拠点の運転者の詳細は404になる", %{conn: conn, manager_b_scope: scope_b} do
      other = driver_fixture(scope_b)

      assert_raise Ecto.NoResultsError, fn -> live(conn, ~p"/management/drivers/#{other}") end
    end

    test "他拠点の運転者の編集画面も404になる", %{conn: conn, manager_b_scope: scope_b} do
      other = driver_fixture(scope_b)

      assert_raise Ecto.NoResultsError, fn ->
        live(conn, ~p"/management/drivers/#{other}/edit")
      end
    end

    test "一般利用者はアクセスできない", %{conn: conn, office_a: office_a} do
      member = user_fixture(%{office_id: office_a.id})

      assert {:error, {:redirect, %{to: "/", flash: flash}}} =
               conn |> log_in_user(member) |> live(~p"/management/drivers")

      assert flash["error"] == "このページを表示する権限がありません"
    end
  end
end
