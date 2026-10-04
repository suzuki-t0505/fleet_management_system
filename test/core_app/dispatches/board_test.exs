defmodule CoreApp.Dispatches.BoardTest do
  use ExUnit.Case, async: true

  alias CoreApp.Dispatches.Board
  alias CoreApp.Dispatches.Delivery
  alias CoreApp.Dispatches.Dispatch

  # 2026-10-01（JST）= 2026-09-30 15:00 UTC 〜 2026-10-01 15:00 UTC
  @date ~D[2026-10-01]

  @vehicle %{id: "veh-1", plate_number: "品川100あ1"}
  @driver %{id: "drv-1", name: "運転 太郎"}

  defp dispatch(started_at, ended_at, attrs \\ %{}) do
    struct!(
      %Dispatch{
        id: "d-#{System.unique_integer([:positive])}",
        title: "配送",
        started_at: started_at,
        ended_at: ended_at,
        shipper_id: "shipper-1",
        shipper: %{id: "shipper-1", name: "北海道物流"},
        vehicle_id: @vehicle.id,
        vehicle: @vehicle,
        driver_id: @driver.id,
        driver: @driver,
        deliveries: []
      },
      attrs
    )
  end

  # JSTの時刻（時, 分）をUTCにして返す
  defp jst(hour, minute \\ 0, date \\ @date) do
    date
    |> DateTime.new!(Time.new!(hour, minute, 0), "Etc/UTC")
    |> DateTime.add(-9, :hour)
  end

  defp build(dispatches, rows \\ [], axis \\ :vehicle),
    do: Board.build(dispatches, rows, @date, axis)

  describe "day_range/1" do
    test "JSTの0:00から24時間をUTCで返す" do
      assert {~U[2026-09-30 15:00:00Z], ~U[2026-10-01 15:00:00Z]} = Board.day_range(@date)
    end
  end

  describe "now_position/2" do
    test "今日（JST）なら位置を%で返し、それ以外はnil" do
      assert Board.now_position(@date, jst(12)) == 50.0
      assert Board.now_position(@date, jst(6)) == 25.0
      assert Board.now_position(@date, jst(0)) == 0.0
      assert Board.now_position(@date, jst(0, 0, ~D[2026-10-02])) == nil
      assert Board.now_position(@date, jst(23, 59, ~D[2026-09-30])) == nil
    end
  end

  describe "build/4 のバーの位置" do
    test "その日の0:00〜24:00に対する left と width を%で返す" do
      %{rows: [%{bars: [bar]}]} = build([dispatch(jst(9), jst(15))])

      assert bar.left == 37.5
      assert bar.width == 25.0
      assert bar.lane == 0
      refute bar.overlap
      refute bar.continues_from_prev
      refute bar.continues_to_next
    end

    test "前日から続く配車は0:00で切り、続きのフラグを立てる" do
      yesterday = Date.add(@date, -1)

      %{rows: [%{bars: [bar]}]} = build([dispatch(jst(22, 0, yesterday), jst(3))])

      assert bar.left == 0.0
      assert bar.width == 12.5
      assert bar.continues_from_prev
      refute bar.continues_to_next
    end

    test "翌日へ続く配車は24:00で切り、続きのフラグを立てる" do
      tomorrow = Date.add(@date, 1)

      %{rows: [%{bars: [bar]}]} = build([dispatch(jst(21), jst(6, 0, tomorrow))])

      assert bar.left == 87.5
      assert bar.width == 12.5
      refute bar.continues_from_prev
      assert bar.continues_to_next
    end

    test "その日をまたいで覆う配車は全幅になる" do
      yesterday = Date.add(@date, -1)
      tomorrow = Date.add(@date, 1)

      %{rows: [%{bars: [bar]}]} = build([dispatch(jst(20, 0, yesterday), jst(4, 0, tomorrow))])

      assert {bar.left, bar.width} == {0.0, 100.0}
      assert bar.continues_from_prev and bar.continues_to_next
    end
  end

  describe "build/4 の重なり" do
    test "重ならない配車は同じレーンに並び、重なりの強調もない" do
      a = dispatch(jst(8), jst(10))
      b = dispatch(jst(11), jst(12))

      %{rows: [%{lanes: 1, bars: bars}]} = build([a, b])

      assert Enum.all?(bars, &(&1.lane == 0 and not &1.overlap))
    end

    test "終了と開始がちょうど一致する配車は重ならない" do
      %{rows: [%{lanes: 1, bars: [first, second]}]} =
        build([dispatch(jst(8), jst(10)), dispatch(jst(10), jst(11))])

      refute first.overlap
      refute second.overlap
    end

    test "重なる配車は別のレーンにずらし、どちらも重なりとして強調する" do
      a = dispatch(jst(8), jst(12))
      b = dispatch(jst(10), jst(14))

      %{rows: [%{lanes: 2, bars: bars}]} = build([a, b])

      assert Enum.map(bars, & &1.lane) == [0, 1]
      assert Enum.all?(bars, & &1.overlap)
    end

    test "レーンは空いた上の段から再利用する" do
      a = dispatch(jst(8), jst(10))
      b = dispatch(jst(9), jst(13))
      c = dispatch(jst(10), jst(11))

      %{rows: [%{lanes: 2, bars: bars}]} = build([a, b, c])

      by_id = Map.new(bars, &{&1.dispatch.id, &1})
      assert by_id[a.id].lane == 0
      assert by_id[b.id].lane == 1
      assert by_id[c.id].lane == 0
      # c は a とは接するだけだが、b とは重なる
      assert by_id[c.id].overlap
    end

    test "別の車両の配車は重ならない" do
      a = dispatch(jst(8), jst(12))

      b =
        dispatch(jst(8), jst(12), %{
          vehicle_id: "veh-2",
          vehicle: %{id: "veh-2", plate_number: "品川100あ2"}
        })

      %{rows: rows} = build([a, b])

      assert length(rows) == 2

      assert Enum.all?(
               rows,
               &(&1.lanes == 1 and Enum.all?(&1.bars, fn bar -> not bar.overlap end))
             )
    end
  end

  describe "build/4 の行" do
    test "配車の無い行も残す" do
      rows = [%{id: "veh-1", name: "品川100あ1"}, %{id: "veh-2", name: "空き車両"}]

      %{rows: result} = build([dispatch(jst(8), jst(10))], rows)

      assert [%{row: %{id: "veh-1"}, bars: [_]}, %{row: %{id: "veh-2"}, bars: [], lanes: 1}] =
               result
    end

    test "行に無い車両の配車は末尾に行を追加する" do
      rows = [%{id: "veh-2", name: "空き車両"}]

      %{rows: [first, second]} = build([dispatch(jst(8), jst(10))], rows)

      assert first.row.id == "veh-2"
      assert second.row == %{id: "veh-1", name: "品川100あ1"}
      assert [_] = second.bars
    end

    test "ドライバー軸ではドライバーごとの行にまとめる" do
      other = %{id: "drv-2", name: "運転 次郎"}

      a = dispatch(jst(8), jst(10))
      b = dispatch(jst(8), jst(10), %{driver_id: other.id, driver: other})

      %{rows: rows} = build([a, b], [], :driver)

      assert rows |> Enum.map(& &1.row.name) |> Enum.sort() == ["運転 太郎", "運転 次郎"]
    end

    test "配車も行も無ければ空" do
      assert %{rows: [], legend: []} = build([])
    end
  end

  describe "build/4 の印と色" do
    test "荷積み・荷降ろしをバー内の位置（%）で返し、時刻順に並べる" do
      deliveries = [
        %Delivery{destination: "横浜", loading_at: jst(12), unloading_at: jst(13)},
        %Delivery{destination: "東京", loading_at: jst(9), unloading_at: nil}
      ]

      %{rows: [%{bars: [bar]}]} = build([dispatch(jst(9), jst(13), %{deliveries: deliveries})])

      assert [
               %{kind: :loading, left: left0, destination: "東京"},
               %{kind: :loading, left: 75.0, destination: "横浜"},
               %{kind: :unloading, left: 100.0, destination: "横浜"}
             ] = bar.markers

      assert left0 == 0.0
    end

    test "その日の範囲外の時刻の印は出さない" do
      yesterday = Date.add(@date, -1)

      deliveries = [
        %Delivery{destination: "東京", loading_at: jst(22, 0, yesterday), unloading_at: jst(1)}
      ]

      %{rows: [%{bars: [bar]}]} =
        build([dispatch(jst(22, 0, yesterday), jst(3), %{deliveries: deliveries})])

      assert [%{kind: :unloading, destination: "東京"}] = bar.markers
    end

    test "荷主ごとに色を割り当て、同じ荷主は同じ色、凡例に出す" do
      other = %{id: "shipper-2", name: "九州運輸"}

      a = dispatch(jst(8), jst(9))
      b = dispatch(jst(10), jst(11))
      c = dispatch(jst(12), jst(13), %{shipper_id: other.id, shipper: other})

      %{rows: [%{bars: bars}], legend: legend} = build([a, b, c])

      colors = Map.new(bars, &{&1.dispatch.id, &1.color})
      assert colors[a.id] == colors[b.id]
      refute colors[a.id] == colors[c.id]
      assert Enum.all?(Map.values(colors), &(&1 in 0..(Board.palette_size() - 1)))

      assert Enum.map(legend, & &1.shipper.name) == ["九州運輸", "北海道物流"]
    end
  end
end
