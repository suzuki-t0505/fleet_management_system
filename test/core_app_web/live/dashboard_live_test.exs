defmodule CoreAppWeb.DashboardLiveTest do
  use CoreAppWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import CoreApp.AccountsFixtures

  describe "未ログイン" do
    test "ログイン画面にリダイレクトする", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/")
    end
  end

  describe "一般利用者" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "ダッシュボードが表示される", %{conn: conn, user: user} do
      {:ok, _lv, html} = live(conn, ~p"/")

      assert html =~ "ダッシュボード"
      assert html =~ user.name
      assert html =~ "一般利用者"
    end

    test "管理者・運行管理者向けのナビゲーションは表示されない", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/")

      assert html =~ "運行日報"
      refute html =~ "運転者"
      refute html =~ "監査ログ"
    end
  end

  describe "運行管理者" do
    setup %{conn: conn} do
      user = manager_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "運行管理者向けのナビゲーションが表示される", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/")

      assert html =~ "運転者"
      assert html =~ "点検整備"
      assert html =~ "期限アラート"
      assert html =~ "運行管理者"
      refute html =~ "監査ログ"
    end
  end

  describe "管理者" do
    setup %{conn: conn} do
      user = admin_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "すべてのナビゲーションが表示される", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/")

      assert html =~ "運転者"
      assert html =~ "監査ログ"
      assert html =~ "拠点"
    end
  end
end
