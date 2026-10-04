defmodule CoreAppWeb.ShipperLive.Labels do
  @moduledoc "荷主の列挙値を日本語表示に変換するモジュールです。"

  alias CoreApp.Shippers.Shipper

  @statuses %{active: "有効", inactive: "無効"}

  @doc """
  荷主ステータスの表示名を返します。
  """
  def status(nil), do: "-"
  def status(value), do: Map.fetch!(@statuses, value)

  @doc """
  荷主ステータスのセレクト用選択肢を返します。
  """
  def status_options do
    Enum.map(Shipper.statuses(), fn value -> {Map.fetch!(@statuses, value), value} end)
  end
end
