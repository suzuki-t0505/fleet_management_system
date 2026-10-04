defmodule CoreAppWeb.McpControllerTest do
  use CoreAppWeb.ConnCase, async: true

  import CoreApp.AccountsFixtures
  import CoreApp.DriversFixtures
  import CoreApp.OfficesFixtures
  import CoreApp.ShippersFixtures
  import CoreApp.VehiclesFixtures

  alias CoreApp.Accounts
  alias CoreApp.Accounts.Scope
  alias CoreApp.Dispatches.Dispatch

  defp setup_manager(%{conn: conn}) do
    office = office_fixture(%{"name" => "A営業所"})
    user = manager_fixture(%{office_id: office.id})
    scope = Scope.for_user(user)

    vehicle_fixture(scope, %{"plate_number" => "品川100あ1234"})
    driver_fixture(scope, %{"code" => "D001", "name" => "山田 太郎"})
    shipper_fixture(scope, %{"code" => "S001", "name" => "テスト運輸"})

    %{conn: authorized(conn, user), user: user, scope: scope}
  end

  defp authorized(conn, user) do
    put_req_header(conn, "authorization", "Bearer " <> Accounts.generate_mcp_token(user))
  end

  defp rpc(conn, method, params \\ %{}, id \\ 1) do
    post(conn, ~p"/mcp", %{"jsonrpc" => "2.0", "id" => id, "method" => method, "params" => params})
  end

  defp call_tool(conn, name, arguments) do
    conn
    |> rpc("tools/call", %{"name" => name, "arguments" => arguments})
    |> json_response(200)
    |> Map.fetch!("result")
  end

  defp row(attrs \\ %{}) do
    Map.merge(
      %{
        "title" => "横浜-大阪",
        "shipper" => "テスト運輸",
        "vehicle" => "品川100あ1234",
        "driver" => "山田太郎",
        "started_at" => "2026-10-04T09:00",
        "ended_at" => "2026-10-04T18:00",
        "course_fare_yen" => 50_000
      },
      attrs
    )
  end

  describe "認証" do
    test "トークンが無ければ401", %{conn: conn} do
      conn = rpc(conn, "ping")

      assert json_response(conn, 401)["error"] == "unauthorized"
      assert get_resp_header(conn, "www-authenticate") == ["Bearer"]
    end

    test "不正なトークンは401", %{conn: conn} do
      conn = conn |> put_req_header("authorization", "Bearer xxxx") |> rpc("ping")

      assert json_response(conn, 401)
    end

    test "無効化された利用者のトークンは401", %{conn: conn} do
      user = manager_fixture()
      token = Accounts.generate_mcp_token(user)
      user |> Ecto.Changeset.change(active: false) |> CoreApp.Repo.update!()

      conn = conn |> put_req_header("authorization", "Bearer " <> token) |> rpc("ping")

      assert json_response(conn, 401)
    end

    test "セッションのトークンでは使えない", %{conn: conn} do
      user = manager_fixture()
      token = user |> Accounts.generate_user_session_token() |> Base.url_encode64(padding: false)

      conn = conn |> put_req_header("authorization", "Bearer " <> token) |> rpc("ping")

      assert json_response(conn, 401)
    end

    test "運行管理者未満はツールを使えない", %{conn: conn} do
      member = user_fixture(%{role: :member})

      result = conn |> authorized(member) |> call_tool("list_vehicles", %{})

      assert result["isError"]
      assert result["structuredContent"]["error"] =~ "運行管理者以上"
    end
  end

  describe "プロトコル" do
    setup :setup_manager

    test "initialize はクライアントのバージョンに合わせて応答する", %{conn: conn} do
      result =
        conn
        |> rpc("initialize", %{"protocolVersion" => "2025-03-26", "capabilities" => %{}})
        |> json_response(200)
        |> Map.fetch!("result")

      assert result["protocolVersion"] == "2025-03-26"
      assert result["capabilities"]["tools"]
      assert result["serverInfo"]["name"]
    end

    test "tools/list に全ツールが載る", %{conn: conn} do
      names =
        conn
        |> rpc("tools/list")
        |> json_response(200)
        |> get_in(["result", "tools"])
        |> Enum.map(& &1["name"])

      assert Enum.sort(names) ==
               ~w(create_dispatches list_dispatches list_drivers list_shippers list_vehicles validate_dispatches)
    end

    test "通知（idなし）には202を返す", %{conn: conn} do
      conn = post(conn, ~p"/mcp", %{"jsonrpc" => "2.0", "method" => "notifications/initialized"})

      assert response(conn, 202) == ""
    end

    test "未対応のメソッドと不明なツールはJSON-RPCエラー", %{conn: conn} do
      assert %{"error" => %{"code" => -32_601}} =
               conn |> rpc("resources/list") |> json_response(200)

      assert %{"error" => %{"code" => -32_602}} =
               conn |> rpc("tools/call", %{"name" => "nothing"}) |> json_response(200)
    end

    test "GETは405", %{conn: conn} do
      assert response(get(conn, ~p"/mcp"), 405)
    end
  end

  describe "マスタの照会" do
    setup :setup_manager

    test "車両をナンバーの表記ゆれを無視して絞り込める", %{conn: conn} do
      result = call_tool(conn, "list_vehicles", %{"q" => "品川１００"})

      assert result["isError"] == false
      assert [%{"plate_number" => "品川100あ1234"}] = result["structuredContent"]["items"]
    end

    test "ドライバーと荷主を返す", %{conn: conn} do
      assert [%{"name" => "山田 太郎"}] =
               call_tool(conn, "list_drivers", %{})["structuredContent"]["items"]

      assert [%{"name" => "テスト運輸"}] =
               call_tool(conn, "list_shippers", %{"q" => "s001"})["structuredContent"]["items"]
    end
  end

  describe "配車の検証と登録" do
    setup :setup_manager

    test "validate_dispatches は保存しない", %{conn: conn} do
      result = call_tool(conn, "validate_dispatches", %{"rows" => [row(%{"ref" => "5"})]})
      data = result["structuredContent"]

      assert data["valid"]
      assert [%{"status" => "ok", "ref" => "5", "summary" => summary}] = data["rows"]
      assert summary["total_amount_yen"] == 50_000
      assert summary["driver"] == "山田 太郎"
      assert CoreApp.Repo.aggregate(Dispatch, :count) == 0
    end

    test "create_dispatches は登録し、list_dispatches で確認できる", %{conn: conn} do
      data = call_tool(conn, "create_dispatches", %{"rows" => [row()]})["structuredContent"]

      assert data["created"]
      assert data["created_count"] == 1
      assert [%{"dispatch_id" => id}] = data["rows"]
      assert is_binary(id)

      listed = call_tool(conn, "list_dispatches", %{"from" => "2026-10-04", "to" => "2026-10-04"})

      assert [%{"id" => ^id, "started_at" => "2026-10-04T09:00", "total_amount_yen" => 50_000}] =
               listed["structuredContent"]["items"]
    end

    test "エラーがあれば何も登録せず、行ごとの理由を返す", %{conn: conn} do
      rows = [row(), row(%{"title" => "別便", "shipper" => "未登録荷主"})]

      data = call_tool(conn, "create_dispatches", %{"rows" => rows})["structuredContent"]

      refute data["created"]
      assert data["error_count"] == 1
      assert [%{"status" => "ok"}, %{"status" => "error", "errors" => [message]}] = data["rows"]
      assert message =~ "荷主「未登録荷主」は登録されていません"
      assert CoreApp.Repo.aggregate(Dispatch, :count) == 0
    end

    test "rows が無ければエラー", %{conn: conn} do
      result = call_tool(conn, "validate_dispatches", %{})

      assert result["isError"]
      assert result["structuredContent"]["error"] =~ "rows"
    end
  end
end
