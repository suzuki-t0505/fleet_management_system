defmodule CoreAppWeb.DispatchLive.Labels do
  @moduledoc "配車の列挙値と金額を表示用に変換するモジュールです。"

  alias CoreApp.Dispatches.Dispatch

  @pricing_types %{course_total: "コース一括", per_delivery: "配送ごと"}

  @doc """
  料金方式の表示名を返します。
  """
  def pricing_type(nil), do: "-"
  def pricing_type(value), do: Map.fetch!(@pricing_types, value)

  @doc """
  料金方式のラジオ用選択肢を返します。
  """
  def pricing_type_options do
    Enum.map(Dispatch.pricing_types(), fn value -> {Map.fetch!(@pricing_types, value), value} end)
  end

  @doc """
  金額（円）を `1,234 円` の形式に整形します。未入力は `-` を返します。
  """
  def yen(nil), do: "-"
  def yen(value), do: "#{delimit(value)} 円"

  defp delimit(number) do
    number
    |> to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end
end
