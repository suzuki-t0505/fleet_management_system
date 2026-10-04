defmodule CoreAppWeb.ApiTokenLive.ManagerTest do
  use CoreAppWeb.ConnCase, async: true

  import Ecto.Query, only: [from: 2]
  import Phoenix.LiveViewTest
  import CoreApp.AccountsFixtures

  alias CoreApp.Accounts
  alias CoreApp.Accounts.Scope
  alias CoreApp.AuditLogs.AuditLog
  alias CoreApp.Repo

  setup %{conn: conn} do
    manager = manager_fixture()
    %{conn: log_in_user(conn, manager), manager: manager, scope: Scope.for_user(manager)}
  end

  test "運行管理者は画面を開ける。トークンが無ければ空の案内を出す", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/management/api_tokens")

    assert html =~ "APIトークン"
    assert html =~ "有効なAPIトークンはありません"
  end

  test "発行すると平文を1回だけ表示し、そのトークンでMCPに接続できる", %{conn: conn, manager: manager} do
    {:ok, lv, _html} = live(conn, ~p"/management/api_tokens")

    html = lv |> element("#create-token") |> render_click()

    assert html =~ "発行しました"
    [_all, token] = Regex.run(~r/id="new-token-value"[^>]*>\s*([\w-]+)\s*</, html)
    assert Accounts.get_user_by_mcp_token(token).id == manager.id
    assert has_element?(lv, "#tokens")

    # 閉じると、トークンの値は画面に残らない
    lv |> element("button", "閉じる") |> render_click()
    refute render(lv) =~ token

    # 再読み込みしても再表示されない
    {:ok, _lv, html} = live(conn, ~p"/management/api_tokens")
    refute html =~ token
    assert html =~ "token-"
  end

  test "失効すると、そのトークンは使えなくなる", %{conn: conn, manager: manager, scope: scope} do
    {:ok, {token, user_token}} = Accounts.create_mcp_token(scope)
    {:ok, lv, _html} = live(conn, ~p"/management/api_tokens")

    html =
      lv
      |> element("#token-#{user_token.id} button", "失効")
      |> render_click()

    assert html =~ "APIトークンを失効しました"
    refute has_element?(lv, "#token-#{user_token.id}")
    refute Accounts.get_user_by_mcp_token(token)
    assert manager
  end

  test "他人のトークンは表示されず、失効もできない", %{conn: conn} do
    other = manager_fixture() |> Scope.for_user()
    {:ok, {token, other_token}} = Accounts.create_mcp_token(other)

    {:ok, lv, html} = live(conn, ~p"/management/api_tokens")
    refute html =~ "token-#{other_token.id}"

    render_click(lv, "revoke", %{"id" => other_token.id})

    assert Accounts.get_user_by_mcp_token(token)
  end

  test "発行と失効は監査ログに残る（トークンの値は残さない）", %{conn: conn, scope: scope} do
    {:ok, lv, _html} = live(conn, ~p"/management/api_tokens")
    lv |> element("#create-token") |> render_click()

    [user_token] = Accounts.list_mcp_tokens(scope)
    lv |> element("#token-#{user_token.id} button", "失効") |> render_click()

    logs = Repo.all(from l in AuditLog, where: l.resource_type == "api_token", order_by: l.id)
    assert Enum.map(logs, & &1.action) == [:create, :delete]
    assert Enum.all?(logs, &(&1.resource_id == user_token.id and is_nil(&1.changes)))
  end

  test "一般利用者は開けない", %{conn: conn} do
    member = user_fixture(%{role: :member})
    conn = log_in_user(conn, member)

    assert {:error, {:redirect, _}} = live(conn, ~p"/management/api_tokens")
  end
end
