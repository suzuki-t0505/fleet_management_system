defmodule CoreAppWeb.MaintenanceLive.Labels do
  @moduledoc "点検整備の列挙値と数値を日本語表示に変換するモジュールです。"

  alias CoreApp.Maintenances.Maintenance

  @categories %{
    inspection: "車検",
    periodic_3m: "3ヶ月点検",
    periodic_12m: "12ヶ月点検",
    daily: "日常点検",
    repair: "修理",
    oil: "オイル交換",
    tire: "タイヤ交換",
    other: "その他"
  }

  @doc """
  区分の表示名を返します。
  """
  def category(nil), do: "-"
  def category(value), do: Map.fetch!(@categories, value)

  @doc """
  区分のセレクト用選択肢を返します。
  """
  def category_options, do: Enum.map(Maintenance.categories(), &{Map.fetch!(@categories, &1), &1})

  @doc """
  区分に応じた「次回予定日」の項目名を返します。

  車検は新しい車検満了日、法定点検は次回の点検予定日を入力させるため、
  同じカラムでもラベルを変えます。
  """
  def next_scheduled_label(:inspection), do: "新しい車検満了日 *"
  def next_scheduled_label(:periodic_3m), do: "次回3ヶ月点検の予定日 *"
  def next_scheduled_label(:periodic_12m), do: "次回12ヶ月点検の予定日 *"
  def next_scheduled_label(_category), do: "次回実施予定日"

  @doc """
  区分ごとに、次回予定日が車両台帳のどこへ反映されるかの説明を返します。
  """
  def next_scheduled_hint(:inspection), do: "車両台帳の車検満了日を、この日付で更新します。"
  def next_scheduled_hint(:periodic_3m), do: "車両台帳の次回3ヶ月点検を、この日付で更新します。"
  def next_scheduled_hint(:periodic_12m), do: "車両台帳の次回12ヶ月点検を、この日付で更新します。"
  def next_scheduled_hint(_category), do: "入力しても車両台帳の期限は更新されません。"

  @doc """
  走行距離計の値を表示用に整形します。
  """
  def odometer(nil), do: "-"
  def odometer(value), do: "#{delimit(value)} km"

  @doc """
  費用を表示用に整形します。
  """
  def cost(nil), do: "-"
  def cost(value), do: "#{delimit(value)} 円"

  defp delimit(number) do
    number
    |> to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end
end
