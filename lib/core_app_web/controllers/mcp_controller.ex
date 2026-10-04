defmodule CoreAppWeb.McpController do
  @moduledoc """
  MCP（Model Context Protocol）のStreamable HTTPエンドポイントです。

  セッションを持たない（stateless）サーバーとして動き、`POST /mcp` のJSON-RPCリクエストに
  JSONで応答します。通知（`id` の無いメッセージ）には 202 を返します。サーバーからの
  プッシュ（SSE）は使わないため、GET と DELETE は 405 を返します。

  認証は `CoreAppWeb.Plugs.McpAuth`、ツールの定義と実行は `CoreAppWeb.Mcp.Tools` が担います。
  """
  use CoreAppWeb, :controller

  alias CoreAppWeb.Mcp.Tools

  @latest_version "2025-06-18"
  @supported_versions ["2025-06-18", "2025-03-26", "2024-11-05"]

  # JSON-RPC のエラーコード
  @invalid_request -32_600
  @method_not_found -32_601
  @invalid_params -32_602

  def handle(conn, %{"jsonrpc" => "2.0", "method" => method} = message) when is_binary(method) do
    case Map.fetch(message, "id") do
      {:ok, id} -> respond(conn, id, dispatch(method, message["params"] || %{}, conn))
      :error -> send_resp(conn, 202, "")
    end
  end

  def handle(conn, _params) do
    json(conn, error_response(nil, @invalid_request, "JSON-RPCリクエストが不正です"))
  end

  def not_allowed(conn, _params) do
    conn
    |> put_resp_header("allow", "POST")
    |> send_resp(405, "")
  end

  defp dispatch("initialize", params, _conn) do
    version = negotiate_version(params["protocolVersion"])

    {:ok,
     %{
       "protocolVersion" => version,
       "capabilities" => %{"tools" => %{"listChanged" => false}},
       "serverInfo" => %{"name" => "fleet-management-system", "version" => "0.1.0"},
       "instructions" =>
         "配車管理システムの操作用サーバーです。表計算ソフトの配車表を取り込む場合は、" <>
           "list_vehicles・list_drivers・list_shippers で名称を確認し、validate_dispatches で検証してから " <>
           "create_dispatches で登録してください。"
     }}
  end

  defp dispatch("ping", _params, _conn), do: {:ok, %{}}

  defp dispatch("tools/list", _params, _conn), do: {:ok, %{"tools" => Tools.definitions()}}

  defp dispatch("tools/call", %{"name" => name} = params, conn) when is_binary(name) do
    context = %{scope: conn.assigns.current_scope, ip_address: ip_address(conn)}

    case Tools.call(name, params["arguments"] || %{}, context) do
      {:ok, result} -> {:ok, tool_result(result, false)}
      {:error, message} -> {:ok, tool_result(%{"error" => message}, true)}
      :unknown_tool -> {:error, @invalid_params, "不明なツールです: #{name}"}
    end
  end

  defp dispatch("tools/call", _params, _conn), do: {:error, @invalid_params, "name が必要です"}

  defp dispatch(method, _params, _conn), do: {:error, @method_not_found, "未対応のメソッドです: #{method}"}

  defp respond(conn, id, {:ok, result}) do
    json(conn, %{"jsonrpc" => "2.0", "id" => id, "result" => result})
  end

  defp respond(conn, id, {:error, code, message}) do
    json(conn, error_response(id, code, message))
  end

  defp error_response(id, code, message) do
    %{"jsonrpc" => "2.0", "id" => id, "error" => %{"code" => code, "message" => message}}
  end

  # 結果はテキスト（JSON）と構造化データの両方で返す
  defp tool_result(data, is_error) do
    %{
      "content" => [%{"type" => "text", "text" => Jason.encode!(data)}],
      "structuredContent" => data,
      "isError" => is_error
    }
  end

  defp negotiate_version(requested) when requested in @supported_versions, do: requested
  defp negotiate_version(_requested), do: @latest_version

  defp ip_address(conn), do: conn.remote_ip |> :inet.ntoa() |> to_string()
end
