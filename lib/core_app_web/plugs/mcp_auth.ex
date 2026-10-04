defmodule CoreAppWeb.Plugs.McpAuth do
  @moduledoc """
  MCPエンドポイントの認証Plugです。

  `Authorization: Bearer <APIトークン>` から利用者を特定し、その利用者の `Scope` を
  `conn.assigns.current_scope` に入れます。MCPのリクエストは状態を持たず、毎回この認証を通ります。
  無効なトークンは 401 を返します。権限（運行管理者以上など）の判定は各Contextが行います。
  """
  import Plug.Conn

  alias CoreApp.Accounts
  alias CoreApp.Accounts.Scope

  def init(opts), do: opts

  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         %Accounts.User{} = user <- Accounts.get_user_by_mcp_token(String.trim(token)) do
      assign(conn, :current_scope, Scope.for_user(user))
    else
      _other -> unauthorized(conn)
    end
  end

  defp unauthorized(conn) do
    body = Jason.encode!(%{error: "unauthorized", message: "APIトークンが無効です"})

    conn
    |> put_resp_content_type("application/json")
    |> put_resp_header("www-authenticate", "Bearer")
    |> send_resp(401, body)
    |> halt()
  end
end
