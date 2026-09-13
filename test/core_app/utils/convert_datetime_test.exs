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
