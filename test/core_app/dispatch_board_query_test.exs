defmodule CoreApp.DispatchBoardQueryTest do
  @moduledoc "配車表向けの取得（list_dispatches_for_day/3）のテストです。"
  use CoreApp.DataCase, async: true

  import CoreApp.AccountsFixtures
  import CoreApp.DispatchesFixtures
  import CoreApp.DriversFixtures
  import CoreApp.OfficesFixtures

  alias CoreApp.Accounts.Scope
  alias CoreApp.Dispatches

  @date ~D[2026-10-01]

  setup do
    office_a = office_fixture(%{"name" => "A営業所"})
    office_b = office_fixture(%{"name" => "B営業所"})

    manager_a = manager_fixture(%{office_id: office_a.id}) |> Scope.for_user()
    manager_b = manager_fixture(%{office_id: office_b.id}) |> Scope.for_user()
    admin = admin_fixture(%{office_id: office_a.id}) |> Scope.for_user()

    %{
      office_a: office_a,
      office_b: office_b,
      manager_a: manager_a,
      manager_b: manager_b,
      admin: admin
    }
  end

  # JST の日時をフォーム形式（タイムゾーン無し）で作る
  defp jst(date, time), do: "#{date}T#{time}"

  defp dispatch_at(scope, from, to, attrs \\ %{}) do
    dispatch_fixture(scope, Map.merge(%{"started_at" => from, "ended_at" => to}, attrs))
  end

  defp ids(dispatches), do: Enum.map(dispatches, & &1.id)

  test "その日と時間が重なる配車だけを返す", %{manager_a: scope} do
    inside = dispatch_at(scope, jst("2026-10-01", "09:00"), jst("2026-10-01", "12:00"))
    from_prev = dispatch_at(scope, jst("2026-09-30", "22:00"), jst("2026-10-01", "02:00"))
    to_next = dispatch_at(scope, jst("2026-10-01", "22:00"), jst("2026-10-02", "03:00"))
    covers = dispatch_at(scope, jst("2026-09-30", "20:00"), jst("2026-10-02", "04:00"))

    _before = dispatch_at(scope, jst("2026-09-30", "09:00"), jst("2026-09-30", "12:00"))
    _after = dispatch_at(scope, jst("2026-10-02", "09:00"), jst("2026-10-02", "12:00"))

    result = Dispatches.list_dispatches_for_day(scope, @date)

    assert Enum.sort(ids(result)) == Enum.sort([inside.id, from_prev.id, to_next.id, covers.id])
  end

  test "境界ちょうど（前日の24:00終了・翌日の0:00開始）は含まない", %{manager_a: scope} do
    dispatch_at(scope, jst("2026-09-30", "20:00"), jst("2026-10-01", "00:00"))
    dispatch_at(scope, jst("2026-10-02", "00:00"), jst("2026-10-02", "03:00"))

    assert Dispatches.list_dispatches_for_day(scope, @date) == []
  end

  test "日付はJSTで切る（UTCでは前日でもJSTでは当日）", %{manager_a: scope} do
    # 2026-09-30 15:30 UTC = 2026-10-01 00:30 JST
    jst_today = dispatch_at(scope, "2026-09-30T15:30:00Z", "2026-09-30T17:00:00Z")

    assert [%{id: id}] = Dispatches.list_dispatches_for_day(scope, @date)
    assert id == jst_today.id
    assert Dispatches.list_dispatches_for_day(scope, ~D[2026-09-30]) == []
  end

  test "開始時刻の順に返し、荷主・車両・ドライバー・配送先を読み込み済みにする", %{manager_a: scope} do
    later = dispatch_at(scope, jst("2026-10-01", "13:00"), jst("2026-10-01", "15:00"))

    earlier =
      dispatch_at(scope, jst("2026-10-01", "08:00"), jst("2026-10-01", "10:00"), %{
        "deliveries" => %{"0" => %{"destination" => "東京"}}
      })

    assert [first, second] = Dispatches.list_dispatches_for_day(scope, @date)
    assert [first.id, second.id] == [earlier.id, later.id]
    assert first.shipper.name && first.vehicle.plate_number && first.driver.name
    assert [%{destination: "東京"}] = first.deliveries
  end

  test "運行管理者には自拠点の配車だけ、管理者は拠点で絞り込める", ctx do
    mine = dispatch_at(ctx.manager_a, jst("2026-10-01", "09:00"), jst("2026-10-01", "12:00"))
    other = dispatch_at(ctx.manager_b, jst("2026-10-01", "09:00"), jst("2026-10-01", "12:00"))

    assert ids(Dispatches.list_dispatches_for_day(ctx.manager_a, @date)) == [mine.id]

    assert ctx.admin |> Dispatches.list_dispatches_for_day(@date) |> ids() |> Enum.sort() ==
             Enum.sort([mine.id, other.id])

    params = %{"office_id" => ctx.office_b.id}
    assert ids(Dispatches.list_dispatches_for_day(ctx.admin, @date, params)) == [other.id]
  end

  test "一般利用者には自分の配車だけを返す", ctx do
    member_user = user_fixture(%{office_id: ctx.office_a.id})
    driver = driver_fixture(ctx.manager_a, %{"user_id" => member_user.id})
    member = member_user |> CoreApp.Repo.preload(:driver, force: true) |> Scope.for_user()

    mine =
      dispatch_at(ctx.manager_a, jst("2026-10-01", "09:00"), jst("2026-10-01", "12:00"), %{
        "driver_id" => driver.id
      })

    dispatch_at(ctx.manager_a, jst("2026-10-01", "09:00"), jst("2026-10-01", "12:00"))

    assert ids(Dispatches.list_dispatches_for_day(member, @date)) == [mine.id]
  end
end
