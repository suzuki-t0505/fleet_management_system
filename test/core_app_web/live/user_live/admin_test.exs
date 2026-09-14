defmodule CoreAppWeb.UserLive.AdminTest do
  use CoreAppWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions
  import CoreApp.AccountsFixtures
  import CoreApp.OfficesFixtures

  alias CoreApp.Accounts
  alias CoreApp.Accounts.Scope
  alias CoreApp.Accounts.User

  setup %{conn: conn} do
    office = office_fixture(%{"code" => "HQ", "name" => "本社"})
    other_office = office_fixture(%{"code" => "OSK", "name" => "大阪営業所"})
    admin = admin_fixture(%{office_id: office.id, name: "管理 太郎"})

    flush_emails()

    %{
      conn: log_in_user(conn, admin),
      admin: admin,
      scope: Scope.for_user(admin),
      office: office,
      other_office: other_office
    }
  end

  defp flush_emails do
    receive do
      {:email, _email} -> flush_emails()
    after
      0 -> :ok
    end
  end

  describe "一覧" do
    test "ユーザーと状態が表示される", %{conn: conn, office: office} do
      user_fixture(%{name: "一覧 花子", office_id: office.id})

      {:ok, _lv, html} = live(conn, ~p"/management/users")

      assert html =~ "一覧 花子"
      assert html =~ "有効"
    end

    test "無効なユーザーは既定で表示されない", %{conn: conn, office: office} do
      user = user_fixture(%{name: "退職 次郎", office_id: office.id})
      {:ok, _user} = Accounts.update_user_profile(user, %{"active" => false})

      {:ok, lv, html} = live(conn, ~p"/management/users")
      refute html =~ "退職 次郎"

      html = lv |> form("#search-bar", %{"active" => "all"}) |> render_change()
      assert html =~ "退職 次郎"
      assert html =~ "無効"
    end

    test "ロール・拠点・キーワードで絞り込める", %{
      conn: conn,
      admin: admin,
      other_office: other_office
    } do
      manager_fixture(%{name: "運行 花子", office_id: other_office.id})

      {:ok, lv, _html} = live(conn, ~p"/management/users")

      # 氏名はサイドバーにも出るため、一覧にしか出ないメールアドレスで判定する
      html = lv |> form("#search-bar", %{"role" => "manager"}) |> render_change()
      assert html =~ "運行 花子"
      refute html =~ admin.email

      html =
        lv
        |> form("#search-bar", %{"role" => "", "office_id" => other_office.id})
        |> render_change()

      assert html =~ "運行 花子"

      html =
        lv
        |> form("#search-bar", %{"office_id" => "", "q" => "管理"})
        |> render_change()

      assert html =~ admin.email
      refute html =~ "運行 花子"
    end
  end

  describe "登録" do
    test "登録するとログインリンクが送られる", %{conn: conn, office: office} do
      {:ok, lv, _html} = live(conn, ~p"/management/users/new")

      assert {:ok, _index_lv, html} =
               lv
               |> form("#user-form",
                 user: %{
                   "name" => "新規 太郎",
                   "email" => "new-user@example.com",
                   "office_id" => office.id,
                   "role" => "manager"
                 }
               )
               |> render_submit()
               |> follow_redirect(conn)

      assert html =~ "ログインリンクを送信しました"
      assert html =~ "新規 太郎"

      assert_email_sent(fn email ->
        assert email.to == [{"", "new-user@example.com"}]
      end)

      user = Accounts.get_user_by_email("new-user@example.com")
      assert user.role == :manager
      refute user.confirmed_at
    end

    test "重複するメールアドレスはエラーになる", %{conn: conn, admin: admin, office: office} do
      {:ok, lv, _html} = live(conn, ~p"/management/users/new")

      html =
        lv
        |> form("#user-form",
          user: %{
            "name" => "重複 太郎",
            "email" => admin.email,
            "office_id" => office.id,
            "role" => "member"
          }
        )
        |> render_submit()

      assert html =~ "has already been taken"
    end
  end

  describe "編集" do
    test "ロールを変更できる", %{conn: conn, scope: scope, office: office} do
      user = user_fixture(%{name: "昇格 太郎", office_id: office.id})

      {:ok, lv, _html} = live(conn, ~p"/management/users/#{user}/edit")

      assert {:ok, _index_lv, html} =
               lv
               |> form("#user-form", user: %{"role" => "manager"})
               |> render_submit()
               |> follow_redirect(conn)

      assert html =~ "ユーザーを更新しました"
      assert Accounts.get_user!(scope, user.id).role == :manager
    end

    test "メールアドレスは変更できない", %{conn: conn, office: office} do
      user = user_fixture(%{office_id: office.id})

      {:ok, _lv, html} = live(conn, ~p"/management/users/#{user}/edit")

      assert html =~ user.email
      assert html =~ "メールアドレスの変更は、本人が設定画面から行います"
      refute html =~ ~s(name="user[email]")
    end

    test "V-32 自分自身のロールと有効フラグは変更できない", %{conn: conn, admin: admin} do
      {:ok, _lv, html} = live(conn, ~p"/management/users/#{admin}/edit")

      assert html =~ "自分自身のロールと有効フラグは変更できません"
      assert html =~ "disabled"
    end

    test "ログインリンクを再送できる", %{conn: conn, office: office} do
      user = user_fixture(%{office_id: office.id})
      flush_emails()

      {:ok, lv, _html} = live(conn, ~p"/management/users/#{user}/edit")

      html = lv |> element("button", "ログインリンクを送信") |> render_click()

      assert html =~ "ログインリンクを送信しました"
      assert_email_sent(fn email -> assert email.to == [{"", user.email}] end)
    end

    test "ロック中のアカウントを解除できる", %{conn: conn, office: office} do
      user = user_fixture(%{office_id: office.id}) |> set_password()

      locked =
        Enum.reduce(1..10, user, fn _attempt, acc ->
          {:ok, updated} = Accounts.record_failed_attempt(acc)
          updated
        end)

      assert User.locked?(locked)

      {:ok, lv, _html} = live(conn, ~p"/management/users/#{locked}/edit")

      html = lv |> element("button", "ロックを解除") |> render_click()

      assert html =~ "ロックを解除しました"
      refute User.locked?(Accounts.get_user!(locked.id))
    end
  end

  describe "アクセス制御" do
    test "運行管理者は参照できない", %{conn: conn, office: office} do
      manager = manager_fixture(%{office_id: office.id})

      assert {:error, {:redirect, %{to: "/", flash: flash}}} =
               conn |> log_in_user(manager) |> live(~p"/management/users")

      assert flash["error"] == "このページを表示する権限がありません"
    end

    test "一般利用者は参照できない", %{conn: conn, office: office} do
      member = user_fixture(%{office_id: office.id})

      assert {:error, {:redirect, %{to: "/"}}} =
               conn |> log_in_user(member) |> live(~p"/management/users/new")
    end
  end
end
