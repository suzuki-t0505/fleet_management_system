defmodule CoreAppWeb.IncidentLive.Labels do
  @moduledoc "事故・ヒヤリの列挙値を日本語表示に変換するモジュールです。"

  alias CoreApp.Incidents.Incident

  @categories %{
    injury: "人身事故",
    property: "物損事故",
    single: "車両単独・不具合",
    near_miss: "ヒヤリハット"
  }

  @weathers %{
    clear: "晴",
    cloudy: "曇",
    rain: "雨",
    snow: "雪",
    fog: "霧",
    other: "その他"
  }

  @statuses %{
    reported: "報告済み",
    analyzing: "分析中",
    countermeasure_reported: "改善策登録済み",
    closed: "完了"
  }

  @doc """
  区分の表示名を返します。
  """
  def category(nil), do: "-"
  def category(value), do: Map.fetch!(@categories, value)

  @doc """
  天候の表示名を返します。
  """
  def weather(nil), do: "-"
  def weather(value), do: Map.fetch!(@weathers, value)

  @doc """
  ステータスの表示名を返します。
  """
  def status(nil), do: "-"
  def status(value), do: Map.fetch!(@statuses, value)

  @doc """
  区分のセレクト用選択肢を返します。
  """
  def category_options, do: options(Incident.categories(), @categories)

  @doc """
  天候のセレクト用選択肢を返します。
  """
  def weather_options, do: options(Incident.weathers(), @weathers)

  @doc """
  ステータスのセレクト用選択肢を返します。
  """
  def status_options, do: options(Incident.statuses(), @statuses)

  @doc """
  警察への届出の有無の表示名を返します。
  """
  def police_reported(true), do: "届出あり"
  def police_reported(_value), do: "届出なし"

  @doc """
  氏名を伏せるかどうかに応じて、表示する氏名を返します（V-27）。
  """
  def person_name(_name, true), do: "（非公開）"
  def person_name(nil, _anonymize?), do: "-"
  def person_name(name, _anonymize?), do: name

  defp options(values, labels), do: Enum.map(values, &{Map.fetch!(labels, &1), &1})
end
