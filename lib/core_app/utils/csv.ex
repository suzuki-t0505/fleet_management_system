defmodule CoreApp.Utils.Csv do
  @moduledoc """
  CSVの行を組み立てるモジュールです。

  Excel で開いたときに文字化けしないよう、**UTF-8 の BOM** を先頭に出し、
  改行は CRLF にします（RFC 4180）。
  """

  # UTF-8 の BOM。Excel が UTF-8 と判定するために必要。
  @bom "﻿"

  @doc """
  ファイルの先頭に出す BOM を返します。
  """
  def bom, do: @bom

  @doc """
  1行分の値を CSV の文字列（iodata）に変換します。

  ```elixir
  iex> dump_row(["品川100あ1", nil, true]) |> IO.iodata_to_binary()
  "品川100あ1,,はい\\r\\n"
  ```
  """
  def dump_row(values) when is_list(values) do
    NimbleCSV.RFC4180.dump_to_iodata([Enum.map(values, &to_field/1)])
  end

  defp to_field(nil), do: ""
  defp to_field(true), do: "はい"
  defp to_field(false), do: "いいえ"
  defp to_field(%Date{} = date), do: Date.to_iso8601(date)
  defp to_field(%Decimal{} = decimal), do: Decimal.to_string(decimal, :normal)
  defp to_field(value) when is_binary(value), do: value
  defp to_field(value) when is_list(value), do: Enum.map_join(value, " / ", &to_field/1)
  defp to_field(value), do: to_string(value)
end
