defmodule CoreAppWeb.Mcp.Tools do
  @moduledoc """
  MCPのツールの一覧と、ツール名からの呼び出しを担うモジュールです。

  ツールは `CoreAppWeb.Mcp.Tools.*` に置き、それぞれ `tools/0` で次の形のマップのリストを返します。

  ```elixir
  %{
    name: "list_vehicles",
    description: "...",
    input_schema: %{"type" => "object", ...},
    run: fn arguments, context -> {:ok, map} | {:error, message} end
  }
  ```

  `context` は `%{scope: %Scope{}, ip_address: String.t()}` です。ツールはContextの公開APIだけを
  呼びます。MCPは運行管理者以上のみ使えます（配車の取り込みが目的のため）。権限と拠点の範囲は、
  Context が `Scope` で判定します。
  """

  alias CoreApp.Accounts.Scope
  alias CoreAppWeb.Mcp.Tools.Dispatches
  alias CoreAppWeb.Mcp.Tools.Masters

  @modules [Masters, Dispatches]

  @doc """
  `tools/list` の応答に載せるツールの定義を返します。
  """
  def definitions do
    Enum.map(all(), fn tool ->
      %{
        "name" => tool.name,
        "description" => tool.description,
        "inputSchema" => tool.input_schema
      }
    end)
  end

  @doc """
  ツールを実行します。

  成功は `{:ok, map}`、ツール内で起きたエラーは `{:error, message}`、未定義のツール名は
  `:unknown_tool` を返します。
  """
  def call(name, arguments, %{scope: scope} = context) do
    case Enum.find(all(), &(&1.name == name)) do
      nil -> :unknown_tool
      tool -> run(tool, arguments, scope, context)
    end
  end

  defp run(tool, arguments, scope, context) do
    if Scope.manager?(scope) do
      tool.run.(arguments, context)
    else
      {:error, "MCPは運行管理者以上のユーザーのみ使えます"}
    end
  end

  defp all, do: Enum.flat_map(@modules, & &1.tools())
end
