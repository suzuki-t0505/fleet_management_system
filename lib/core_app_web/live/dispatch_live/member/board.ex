defmodule CoreAppWeb.DispatchLive.Member.Board do
  @moduledoc false
  use CoreAppWeb, :live_view

  alias CoreApp.Dispatches
  alias CoreApp.Dispatches.Board
  alias CoreApp.Utils.ConvertDatetime

  alias CoreAppWeb.DispatchLive.BoardComponents

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "配車表")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    date = parse_date(params["date"])

    # 自分の配車だけが返る（スコープは Context が適用する）。行は配車のある車両だけ
    dispatches = Dispatches.list_dispatches_for_day(socket.assigns.current_scope, date)

    {:noreply,
     socket
     |> assign(date: date)
     |> assign(board: Board.build(dispatches, [], date, :vehicle))
     |> assign(now: Board.now_position(date))}
  end

  @impl true
  def handle_event("filter", %{"date" => date}, socket) do
    {:noreply, push_patch(socket, to: board_path(parse_date(date)))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <:actions>
        <.link
          navigate={~p"/dispatches"}
          class="text-button rounded-md border border-hairline bg-surface px-4 py-2 text-ink hover:bg-canvas-soft"
        >
          配車一覧
        </.link>
      </:actions>

      <div class="space-y-6">
        <div class="flex flex-col gap-3 rounded-lg border border-hairline bg-surface p-4 lg:flex-row lg:items-end">
          <BoardComponents.date_nav date={@date} path={&board_path/1} />

          <form id="board-filter" phx-change="filter">
            <label class="text-eyebrow text-ink-muted" for="board-date">日付</label>
            <input
              type="date"
              id="board-date"
              name="date"
              value={Date.to_iso8601(@date)}
              class="text-body-sm mt-1 block w-full rounded-xs border border-hairline bg-surface px-2 py-2 text-ink lg:w-44"
            />
          </form>
        </div>

        <h2 class="text-title" id="board-date-title">{format_heading(@date)}</h2>

        <BoardComponents.board
          board={@board}
          now={@now}
          show_path={&~p"/dispatches/#{&1}"}
        />
      </div>
    </Layouts.app>
    """
  end

  defp board_path(date), do: ~p"/dispatches/board?#{%{"date" => Date.to_iso8601(date)}}"

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _error -> ConvertDatetime.today()
    end
  end

  defp parse_date(_value), do: ConvertDatetime.today()

  defp format_heading(date) do
    weekday = Enum.at(~w(月 火 水 木 金 土 日), Date.day_of_week(date) - 1)
    "#{date.year}年#{date.month}月#{date.day}日（#{weekday}）"
  end
end
