defmodule CoreApp.Utils.CsvTest do
  use ExUnit.Case, async: true

  alias CoreApp.Utils.Csv

  defp dump(values), do: values |> Csv.dump_row() |> IO.iodata_to_binary()

  test "BOM を返す" do
    assert Csv.bom() == "﻿"
  end

  test "改行は CRLF になる" do
    assert dump(["a", "b"]) == "a,b\r\n"
  end

  test "カンマと引用符をエスケープする" do
    assert dump(["備考,あり", ~s(引用"符)]) == ~s("備考,あり","引用""符"\r\n)
  end

  test "nil は空欄、真偽値は日本語にする" do
    assert dump([nil, true, false]) == ",はい,いいえ\r\n"
  end

  test "日付・小数・リストを整形する" do
    assert dump([~D[2026-09-14], Decimal.new("40.50"), [:a, :b]]) ==
             "2026-09-14,40.50,a / b\r\n"
  end
end
