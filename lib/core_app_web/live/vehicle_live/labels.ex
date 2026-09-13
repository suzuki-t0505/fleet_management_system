defmodule CoreAppWeb.VehicleLive.Labels do
  @moduledoc "車両の列挙値を日本語表示に変換するモジュールです。"

  alias CoreApp.Vehicles.Vehicle

  @vehicle_classes %{
    large: "大型",
    medium: "中型",
    semi_medium: "準中型",
    ordinary: "普通",
    light: "軽",
    other: "その他"
  }

  @statuses %{
    active: "稼働中",
    maintenance: "整備中",
    idle: "休車",
    scrapped: "廃車"
  }

  @fuel_types %{
    diesel: "軽油",
    gasoline: "ガソリン",
    hybrid: "ハイブリッド",
    ev: "電気",
    other: "その他"
  }

  @ownerships %{owned: "自社所有", lease: "リース"}

  @doc """
  車種区分の表示名を返します。
  """
  def vehicle_class(nil), do: "-"
  def vehicle_class(value), do: Map.fetch!(@vehicle_classes, value)

  @doc """
  車両ステータスの表示名を返します。
  """
  def status(nil), do: "-"
  def status(value), do: Map.fetch!(@statuses, value)

  @doc """
  燃料種別の表示名を返します。
  """
  def fuel_type(nil), do: "-"
  def fuel_type(value), do: Map.fetch!(@fuel_types, value)

  @doc """
  所有区分の表示名を返します。
  """
  def ownership(nil), do: "-"
  def ownership(value), do: Map.fetch!(@ownerships, value)

  @doc """
  車種区分のセレクト用選択肢を返します。
  """
  def vehicle_class_options, do: options(Vehicle.vehicle_classes(), @vehicle_classes)

  @doc """
  車両ステータスのセレクト用選択肢を返します。
  """
  def status_options, do: options(Vehicle.statuses(), @statuses)

  @doc """
  燃料種別のセレクト用選択肢を返します。
  """
  def fuel_type_options, do: options(Vehicle.fuel_types(), @fuel_types)

  @doc """
  所有区分のセレクト用選択肢を返します。
  """
  def ownership_options, do: options(Vehicle.ownerships(), @ownerships)

  defp options(values, labels) do
    Enum.map(values, fn value -> {Map.fetch!(labels, value), value} end)
  end
end
