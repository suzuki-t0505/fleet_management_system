defmodule CoreAppWeb.DispatchLive.BoardComponents do
  @moduledoc """
  配車表（1日のタイムライン）の描画コンポーネントです。管理者向けと一般利用者向けで共通です。

  位置と重なりの計算は `CoreApp.Dispatches.Board` が行い、ここでは受け取った値をHTML/CSSに描くだけです。
  色・角丸・寸法は `docs/DESIGN-notion.md` の「Timeline (配車表)」に従います。
  """
  use CoreAppWeb, :html

  alias CoreApp.Utils.ConvertDatetime

  # DESIGN-notion.md の timeline-bar のパレット。Board.palette_size/0 と数を合わせる。
  # Tailwind が検出できるよう、クラス名は完全な文字列で書く。
  @bar_colors %{
    0 => "bg-primary",
    1 => "bg-accent-teal",
    2 => "bg-accent-green",
    3 => "bg-accent-purple-deep",
    4 => "bg-accent-brown",
    5 => "bg-secondary"
  }

  # レーン1段の高さ（バー36px + 上下の余白）
  @lane_height 44

  @doc """
  前日・今日・翌日への移動リンクです。
  """
  attr :date, Date, required: true
  attr :path, :any, required: true, doc: "日付を受け取り、遷移先のパスを返す関数"

  def date_nav(assigns) do
    ~H"""
    <div class="flex items-center gap-2">
      <.link
        patch={@path.(Date.add(@date, -1))}
        id="board-prev"
        class="text-button rounded-md border border-hairline bg-surface px-3 py-2 text-ink hover:bg-canvas-soft"
        aria-label="前日"
      >
        <.icon name="hero-chevron-left" class="size-4" />
      </.link>
      <.link
        patch={@path.(ConvertDatetime.today())}
        id="board-today"
        class="text-button rounded-md border border-hairline bg-surface px-3 py-2 text-ink hover:bg-canvas-soft"
      >
        今日
      </.link>
      <.link
        patch={@path.(Date.add(@date, 1))}
        id="board-next"
        class="text-button rounded-md border border-hairline bg-surface px-3 py-2 text-ink hover:bg-canvas-soft"
        aria-label="翌日"
      >
        <.icon name="hero-chevron-right" class="size-4" />
      </.link>
    </div>
    """
  end

  @doc """
  配車表です。`board` は `CoreApp.Dispatches.Board.build/4` の返り値です。
  """
  attr :board, :map, required: true
  attr :now, :any, default: nil, doc: "現在時刻の位置（%）。今日でなければ nil"
  attr :row_label, :string, default: "車両"
  attr :show_path, :any, required: true, doc: "配車を受け取り、詳細のパスを返す関数"

  def board(assigns) do
    ~H"""
    <div class="space-y-3">
      <div id="dispatch-board" class="overflow-x-auto rounded-lg border border-hairline bg-surface">
        <div class="min-w-[960px]">
          <div class="flex bg-canvas-soft">
            <div class="text-eyebrow sticky left-0 z-20 w-40 shrink-0 bg-canvas-soft px-3 py-3 text-ink-muted">
              {@row_label}
            </div>
            <div class="relative h-10 flex-1">
              <span
                :for={hour <- 0..22//2}
                class="text-eyebrow absolute top-3 pl-1 text-ink-muted"
                style={"left: #{hour_position(hour)}%"}
              >
                {hour}時
              </span>
            </div>
          </div>

          <div
            :for={row <- @board.rows}
            id={"board-row-#{row.row.id}"}
            class="flex border-t border-hairline"
          >
            <div class="text-body-sm sticky left-0 z-20 w-40 shrink-0 bg-surface px-3 py-3 text-ink">
              {row.row.name}
            </div>
            <div class="relative flex-1" style={"height: #{row.lanes * lane_height() + 8}px"}>
              <div
                :for={hour <- 1..23}
                class="absolute inset-y-0 border-l border-hairline"
                style={"left: #{hour_position(hour)}%"}
              >
              </div>
              <div
                :if={@now}
                class="absolute inset-y-0 z-10 w-0.5 bg-accent-pink"
                style={"left: #{@now}%"}
                title="現在時刻"
              >
              </div>

              <.link
                :for={bar <- row.bars}
                id={"board-bar-#{bar.dispatch.id}"}
                navigate={@show_path.(bar.dispatch)}
                class={[
                  "text-caption absolute z-10 flex h-9 items-center gap-1 overflow-hidden px-2 text-on-primary hover:opacity-90",
                  Map.fetch!(bar_colors(), bar.color),
                  bar.continues_from_prev && "rounded-l-xs rounded-r-md",
                  bar.continues_to_next && "rounded-l-md rounded-r-xs",
                  bar.continues_from_prev && bar.continues_to_next && "rounded-xs",
                  !bar.continues_from_prev && !bar.continues_to_next && "rounded-md",
                  bar.overlap && "border-2 border-accent-orange"
                ]}
                style={"left: #{bar.left}%; width: #{bar.width}%; top: #{bar.lane * lane_height() + 4}px"}
                title={bar_title(bar)}
              >
                <span :if={bar.continues_from_prev} aria-label="前日から続く">←</span>
                <span class="truncate">{bar.dispatch.title}</span>
                <span class="truncate opacity-80">{time_range(bar.dispatch)}</span>
                <span :if={bar.continues_to_next} class="ml-auto" aria-label="翌日へ続く">→</span>
                <span
                  :for={marker <- bar.markers}
                  class={[
                    "absolute -translate-x-1/2 text-[10px] leading-none text-on-primary",
                    marker.kind == :loading && "bottom-0",
                    marker.kind == :unloading && "top-0"
                  ]}
                  style={"left: #{marker.left}%"}
                  title={marker_title(marker)}
                >
                  {marker_symbol(marker.kind)}
                </span>
              </.link>
            </div>
          </div>

          <p
            :if={@board.rows == []}
            class="text-body-sm border-t border-hairline px-3 py-6 text-ink-muted"
          >
            表示できる行がありません。
          </p>
        </div>
      </div>

      <div
        id="board-legend"
        class="text-caption flex flex-wrap items-center gap-x-4 gap-y-2 text-ink-secondary"
      >
        <span :for={item <- @board.legend} class="inline-flex items-center gap-1">
          <span class={["inline-block size-3 rounded-xs", Map.fetch!(bar_colors(), item.color)]}></span>
          {item.shipper.name}
        </span>
        <span class="inline-flex items-center gap-1">
          <span class="inline-block size-3 rounded-xs border-2 border-accent-orange bg-surface"></span>
          時間が重なる配車
        </span>
        <span class="inline-flex items-center gap-1">▲ 荷積み ▼ 荷降ろし</span>
        <span class="inline-flex items-center gap-1">← → 前日から続く／翌日へ続く</span>
      </div>
    </div>
    """
  end

  defp bar_colors, do: @bar_colors
  defp lane_height, do: @lane_height

  defp hour_position(hour), do: Float.round(hour / 24 * 100, 3)

  defp marker_symbol(:loading), do: "▲"
  defp marker_symbol(:unloading), do: "▼"

  defp marker_kind(:loading), do: "荷積み"
  defp marker_kind(:unloading), do: "荷降ろし"

  defp marker_title(marker) do
    "#{marker_kind(marker.kind)} #{marker.destination} #{format_datetime(marker.at)}"
  end

  defp bar_title(bar) do
    dispatch = bar.dispatch

    "#{dispatch.title}（#{dispatch.shipper.name}）#{format_datetime(dispatch.started_at)} 〜 #{format_datetime(dispatch.ended_at)}"
  end

  defp time_range(dispatch) do
    "#{format_time(dispatch.started_at)}-#{format_time(dispatch.ended_at)}"
  end

  defp format_time(datetime) do
    jst = ConvertDatetime.to_jst(datetime)

    "#{jst.hour}:#{jst.minute |> to_string() |> String.pad_leading(2, "0")}"
  end
end
