defmodule CoreAppWeb.DriverLive.Labels do
  @moduledoc "運転者の列挙値を日本語表示に変換するモジュールです。"

  alias CoreApp.Drivers.Driver

  @employment_types %{
    full_time: "正社員",
    contract: "契約社員",
    part_time: "パート",
    other: "その他",
    retired: "退職"
  }

  @license_types %{
    large: "大型",
    medium: "中型",
    semi_medium: "準中型",
    ordinary: "普通",
    large_special: "大型特殊",
    towing: "けん引"
  }

  @doc """
  雇用区分の表示名を返します。
  """
  def employment_type(nil), do: "-"
  def employment_type(value), do: Map.fetch!(@employment_types, value)

  @doc """
  免許種類の表示名を返します。
  """
  def license_type(value), do: Map.fetch!(@license_types, value)

  @doc """
  免許種類の一覧を「大型・けん引」の形式で返します。
  """
  def license_types(nil), do: "-"
  def license_types([]), do: "-"

  def license_types(values) when is_list(values) do
    Enum.map_join(values, "・", &license_type/1)
  end

  @doc """
  雇用区分のセレクト用選択肢を返します。
  """
  def employment_type_options, do: options(Driver.employment_types(), @employment_types)

  @doc """
  免許種類のチェックボックス用選択肢を返します。
  """
  def license_type_options, do: options(Driver.license_types(), @license_types)

  defp options(values, labels) do
    Enum.map(values, fn value -> {Map.fetch!(labels, value), value} end)
  end
end
