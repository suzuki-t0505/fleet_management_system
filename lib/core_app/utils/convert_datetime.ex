defmodule CoreApp.Utils.ConvertDatetime do
  @moduledoc """
  UTCで保存した日時をJST（日本標準時）に変換するモジュールです。

  日本標準時は夏時間を持たないため、固定オフセット（+9時間）で変換します。
  「今日」の判定は必ずこのモジュールを経由し、`Date.utc_today/0` を直接使わないでください。
  """

  @jst_offset_hours 9

  @doc """
  JSTの現在日時を返します。
  """
  def now do
    DateTime.utc_now() |> DateTime.add(@jst_offset_hours, :hour)
  end

  @doc """
  JSTの今日の日付を返します。
  """
  def today do
    now() |> DateTime.to_date()
  end

  @doc """
  UTCの日時をJSTに変換します。表示用の変換であり、タイムゾーン情報は付与しません。
  """
  def to_jst(nil), do: nil

  def to_jst(%DateTime{} = datetime) do
    DateTime.add(datetime, @jst_offset_hours, :hour)
  end

  @doc """
  指定した日付までの残日数をJST基準で返します。過去の日付は負数になります。
  """
  def days_until(nil), do: nil

  def days_until(%Date{} = date) do
    Date.diff(date, today())
  end
end
