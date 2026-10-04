defmodule Mix.Tasks.CoreApp.Mcp.GenToken do
  @shortdoc "MCP用のAPIトークンを発行する"

  @moduledoc """
  指定したメールアドレスの利用者のMCP用APIトークンを発行します。

      mix core_app.mcp.gen_token user@example.com

  トークンは表示された1回しか確認できません（DBにはハッシュを保存します）。
  MCPのリクエストはこの利用者の権限・拠点で実行されます。有効期間は90日です。
  運行管理者以上の利用者のみ、MCPを使えます。
  """
  use Mix.Task

  alias CoreApp.Accounts

  @impl Mix.Task
  def run([email]) do
    Mix.Task.run("app.start")

    case Accounts.get_user_by_email(email) do
      nil ->
        Mix.raise("利用者が見つかりません: #{email}")

      %{active: false} ->
        Mix.raise("無効化された利用者です: #{email}")

      user ->
        Mix.shell().info("""
        利用者: #{user.name}（#{user.email} / #{user.role}）

        APIトークン（再表示できません）:
        #{Accounts.generate_mcp_token(user)}
        """)
    end
  end

  def run(_args), do: Mix.raise("使い方: mix core_app.mcp.gen_token <メールアドレス>")
end
