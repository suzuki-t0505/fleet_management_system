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
  `datetime-local` から送られてくる日時（タイムゾーンを持たない文字列）をJSTとみなし、
  UTCに変換します。

  タイムゾーン付きの文字列（`Z` やオフセット）はそのまま返します。APIやテストから
  UTCで渡された値を二重に変換しないためです。
  """
  def parse_input(nil), do: nil
  def parse_input(""), do: ""

  def parse_input(value) when is_binary(value) do
    if timezone?(value) do
      value
    else
      case NaiveDateTime.from_iso8601(pad_seconds(value)) do
        {:ok, naive} ->
          naive
          |> DateTime.from_naive!("Etc/UTC")
          |> DateTime.add(-@jst_offset_hours, :hour)

        _error ->
          value
      end
    end
  end

  def parse_input(value), do: value

  @doc """
  UTCの日時を、フォームの `datetime-local` に表示するためのJSTの日時文字列に変換します。
  """
  def to_input_value(nil), do: nil

  def to_input_value(%DateTime{} = datetime) do
    datetime
    |> to_jst()
    |> DateTime.to_naive()
    |> NaiveDateTime.to_iso8601()
    |> String.slice(0, 16)
  end

  def to_input_value(value), do: value

  defp timezone?(value) do
    String.ends_with?(value, "Z") or Regex.match?(~r/[+-]\d{2}:?\d{2}$/, value)
  end

  defp pad_seconds(value) do
    if Regex.match?(~r/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/, value), do: value <> ":00", else: value
  end

  @doc """
  指定した日付までの残日数をJST基準で返します。過去の日付は負数になります。
  """
  def days_until(nil), do: nil

  def days_until(%Date{} = date) do
    Date.diff(date, today())
  end
end
