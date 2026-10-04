defmodule CoreApp.Dispatches.Board do
  @moduledoc """
  配車表（1日分のタイムライン）の配置を計算する純関数のモジュールです。

  DBには触れません。取得済みの配車を、行（車両またはドライバー）ごとのバーに並べ、
  横位置（その日の0:00〜24:00に対する%）・重なりを避けるレーン・荷積み/荷降ろしの印を返します。
  日付と時刻はすべてJSTで扱い、保存値（UTC）との変換は `ConvertDatetime` と同じ +9時間 です。
  """

  alias CoreApp.Dispatches.Dispatch

  @day_seconds 86_400
  @jst_offset_hours 9

  # 荷主の色分けに使う色数。画面側のパレットの数と合わせる
  @palette_size 6

  @doc """
  色分けに使う色の数を返します。
  """
  def palette_size, do: @palette_size

  @doc """
  指定したJSTの日付の範囲を、UTCの `{開始, 終了}`（開始を含み終了を含まない）で返します。
  """
  def day_range(%Date{} = date) do
    start_at =
      date
      |> DateTime.new!(~T[00:00:00], "Etc/UTC")
      |> DateTime.add(-@jst_offset_hours, :hour)

    {start_at, DateTime.add(start_at, @day_seconds, :second)}
  end

  @doc """
  現在時刻の位置（その日に対する%）を返します。指定日が「今日（JST）」でなければ `nil` です。
  """
  def now_position(%Date{} = date, %DateTime{} = now \\ DateTime.utc_now()) do
    {day_start, day_end} = day_range(date)

    if DateTime.compare(now, day_start) != :lt and DateTime.compare(now, day_end) == :lt do
      percent(DateTime.diff(now, day_start), @day_seconds)
    end
  end

  @doc """
  配車を行ごとのバーに並べます。

  `rows` は表示する行（`%{id: ..., name: ...}`）です。配車が無い行も残して空きが分かるようにします。
  `rows` に無い車両・ドライバーの配車があれば、その行を末尾に追加します
  （廃車・退職済みの車両やドライバーの配車を見落とさないため）。

  配車は `:shipper` `:vehicle` `:driver` `:deliveries` を preload 済みであることを前提にします。

  返り値は `%{rows: [行], legend: [荷主と色]}` です。

  - 行: `%{row: %{id, name}, lanes: レーン数, bars: [バー]}`
  - バー: `%{dispatch, lane, left, width, overlap, continues_from_prev, continues_to_next, color, markers}`
  - 印: `%{kind: :loading | :unloading, left, destination, at}`（`left` はバー内の位置%）
  """
  def build(dispatches, rows, %Date{} = date, axis) when axis in [:vehicle, :driver] do
    {day_start, day_end} = day_range(date)
    colors = color_map(dispatches)

    bars_by_row =
      dispatches
      |> Enum.map(&to_bar(&1, day_start, day_end, colors))
      |> Enum.group_by(&row_id(&1.dispatch, axis))

    rows = merge_rows(rows, dispatches, axis)

    %{
      rows:
        Enum.map(rows, fn row ->
          {bars, lanes} = bars_by_row |> Map.get(row.id, []) |> assign_lanes()
          %{row: row, lanes: max(lanes, 1), bars: bars}
        end),
      legend: legend(dispatches, colors)
    }
  end

  defp to_bar(%Dispatch{} = dispatch, day_start, day_end, colors) do
    shown_start = latest(dispatch.started_at, day_start)
    shown_end = earliest(dispatch.ended_at, day_end)

    %{
      dispatch: dispatch,
      lane: 0,
      left: percent(DateTime.diff(shown_start, day_start), @day_seconds),
      width: percent(DateTime.diff(shown_end, shown_start), @day_seconds),
      overlap: false,
      continues_from_prev: DateTime.before?(dispatch.started_at, day_start),
      continues_to_next: DateTime.after?(dispatch.ended_at, day_end),
      color: Map.fetch!(colors, dispatch.shipper_id),
      markers: markers(dispatch, shown_start, shown_end),
      shown_start: shown_start,
      shown_end: shown_end
    }
  end

  # 荷積み・荷降ろしのうち、その日に表示している範囲内のものを、バー内の位置（%）で返す
  defp markers(%Dispatch{deliveries: deliveries}, shown_start, shown_end) do
    span = DateTime.diff(shown_end, shown_start)

    deliveries
    |> Enum.flat_map(fn delivery ->
      [{:loading, delivery.loading_at}, {:unloading, delivery.unloading_at}]
      |> Enum.reject(fn {_kind, at} -> is_nil(at) end)
      |> Enum.map(fn {kind, at} -> {kind, at, delivery.destination} end)
    end)
    |> Enum.filter(fn {_kind, at, _destination} ->
      DateTime.compare(at, shown_start) != :lt and DateTime.compare(at, shown_end) != :gt
    end)
    |> Enum.map(fn {kind, at, destination} ->
      %{
        kind: kind,
        left: percent(DateTime.diff(at, shown_start), span),
        destination: destination,
        at: at
      }
    end)
    |> Enum.sort_by(&DateTime.to_unix(&1.at))
  end

  # 開始が早い順に、置ける最も上のレーンへ割り当てる。終了と開始がちょうど一致するだけなら重ならない。
  defp assign_lanes(bars) do
    sorted =
      Enum.sort_by(bars, &{DateTime.to_unix(&1.shown_start), DateTime.to_unix(&1.shown_end)})

    {placed, lane_ends} =
      Enum.map_reduce(sorted, [], fn bar, lane_ends ->
        case Enum.find_index(lane_ends, &(DateTime.compare(&1, bar.shown_start) != :gt)) do
          nil -> {%{bar | lane: length(lane_ends)}, lane_ends ++ [bar.shown_end]}
          lane -> {%{bar | lane: lane}, List.replace_at(lane_ends, lane, bar.shown_end)}
        end
      end)

    {mark_overlaps(placed), length(lane_ends)}
  end

  defp mark_overlaps(bars) do
    Enum.map(bars, fn bar ->
      overlap =
        Enum.any?(bars, fn other ->
          other != bar and DateTime.before?(other.shown_start, bar.shown_end) and
            DateTime.after?(other.shown_end, bar.shown_start)
        end)

      %{bar | overlap: overlap}
    end)
  end

  defp merge_rows(rows, dispatches, axis) do
    known = MapSet.new(rows, & &1.id)

    extra =
      dispatches
      |> Enum.map(&row_of(&1, axis))
      |> Enum.reject(&MapSet.member?(known, &1.id))
      |> Enum.uniq_by(& &1.id)
      |> Enum.sort_by(& &1.name)

    rows ++ extra
  end

  defp row_id(%Dispatch{vehicle_id: id}, :vehicle), do: id
  defp row_id(%Dispatch{driver_id: id}, :driver), do: id

  defp row_of(%Dispatch{vehicle: vehicle}, :vehicle),
    do: %{id: vehicle.id, name: vehicle.plate_number}

  defp row_of(%Dispatch{driver: driver}, :driver), do: %{id: driver.id, name: driver.name}

  # 荷主ごとに色を割り当てる。同じ日に出てくる荷主は、色数の範囲内で重複しない
  defp color_map(dispatches) do
    dispatches
    |> Enum.map(& &1.shipper_id)
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.with_index()
    |> Map.new(fn {shipper_id, index} -> {shipper_id, rem(index, @palette_size)} end)
  end

  defp legend(dispatches, colors) do
    dispatches
    |> Enum.map(& &1.shipper)
    |> Enum.uniq_by(& &1.id)
    |> Enum.sort_by(& &1.name)
    |> Enum.map(&%{shipper: &1, color: Map.fetch!(colors, &1.id)})
  end

  defp percent(_seconds, 0), do: 0.0
  defp percent(seconds, total), do: Float.round(seconds / total * 100, 3)

  defp latest(a, b), do: if(DateTime.after?(a, b), do: a, else: b)
  defp earliest(a, b), do: if(DateTime.before?(a, b), do: a, else: b)
end
