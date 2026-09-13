defmodule CoreApp.Utils.ConvertDatetimeTest do
  use ExUnit.Case, async: true

  alias CoreApp.Utils.ConvertDatetime

  describe "to_jst/1" do
    test "UTCの日時を9時間進めて返す" do
      utc = ~U[2026-09-13 00:00:00Z]

      assert ConvertDatetime.to_jst(utc) == ~U[2026-09-13 09:00:00Z]
    end

    test "nil はそのまま返す" do
      assert is_nil(ConvertDatetime.to_jst(nil))
    end
  end

  describe "today/0" do
    test "UTCの日付と一致するか、1日進んでいる" do
      diff = Date.diff(ConvertDatetime.today(), Date.utc_today())

      assert diff in [0, 1]
    end

    test "JSTで日付が変わる時間帯ではUTCより1日進む" do
      # UTC 2026-09-12 15:00 は JST 2026-09-13 00:00
      jst = ConvertDatetime.to_jst(~U[2026-09-12 15:00:00Z])

      assert DateTime.to_date(jst) == ~D[2026-09-13]
      assert Date.diff(DateTime.to_date(jst), ~D[2026-09-12]) == 1
    end
  end

  describe "parse_input/1" do
    test "タイムゾーンを持たない入力はJSTとみなしてUTCに変換する" do
      assert ConvertDatetime.parse_input("2026-09-13T07:30") == ~U[2026-09-12 22:30:00Z]
    end

    test "秒付きの入力も変換する" do
      assert ConvertDatetime.parse_input("2026-09-13T07:30:15") == ~U[2026-09-12 22:30:15Z]
    end

    test "UTC指定（Z）の入力は変換しない" do
      assert ConvertDatetime.parse_input("2026-09-13T07:30:00Z") == "2026-09-13T07:30:00Z"
    end

    test "オフセット付きの入力は変換しない" do
      assert ConvertDatetime.parse_input("2026-09-13T07:30:00+09:00") ==
               "2026-09-13T07:30:00+09:00"
    end

    test "空文字と nil はそのまま返す" do
      assert ConvertDatetime.parse_input("") == ""
      assert is_nil(ConvertDatetime.parse_input(nil))
    end

    test "解釈できない文字列はそのまま返し、changesetでエラーにする" do
      assert ConvertDatetime.parse_input("not a datetime") == "not a datetime"
    end
  end

  describe "to_input_value/1" do
    test "UTCの日時をJSTのフォーム表示値に変換する" do
      assert ConvertDatetime.to_input_value(~U[2026-09-12 22:30:00Z]) == "2026-09-13T07:30"
    end

    test "往復で値が変わらない" do
      input = "2026-09-13T07:30"

      assert input |> ConvertDatetime.parse_input() |> ConvertDatetime.to_input_value() == input
    end

    test "nil はそのまま返す" do
      assert is_nil(ConvertDatetime.to_input_value(nil))
    end
  end

  describe "days_until/1" do
    test "未来の日付は正の残日数を返す" do
      assert ConvertDatetime.days_until(Date.add(ConvertDatetime.today(), 30)) == 30
    end

    test "当日は0を返す" do
      assert ConvertDatetime.days_until(ConvertDatetime.today()) == 0
    end

    test "過去の日付は負数を返す" do
      assert ConvertDatetime.days_until(Date.add(ConvertDatetime.today(), -3)) == -3
    end

    test "nil は nil を返す" do
      assert is_nil(ConvertDatetime.days_until(nil))
    end
  end
end
