defmodule CoreAppWeb.DispatchLive.Manager.Board do
  @moduledoc false
  use CoreAppWeb, :live_view

  alias CoreApp.Accounts.Scope
  alias CoreApp.Dispatches
  alias CoreApp.Dispatches.Board
  alias CoreApp.Drivers
  alias CoreApp.Offices
  alias CoreApp.Utils.ConvertDatetime
  alias CoreApp.Vehicles

  alias CoreAppWeb.DispatchLive.BoardComponents

  @filter_keys ~w(date axis office_id)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "配車表")
     |> assign(offices: office_options(socket.assigns.current_scope))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    scope = socket.assigns.current_scope
    filters = Map.take(params, @filter_keys)
    date = parse_date(filters["date"])
    axis = parse_axis(filters["axis"])
    office_id = if Scope.admin?(scope), do: blank_to_nil(filters["office_id"])

    dispatches = Dispatches.list_dispatches_for_day(scope, date, %{"office_id" => office_id})
    board = Board.build(dispatches, rows(scope, axis, office_id), date, axis)

    {:noreply,
     socket
     |> assign(date: date, axis: axis, office_id: office_id)
     |> assign(board: board, now: Board.now_position(date))}
  end

  @impl true
  def handle_event("filter", params, socket) do
    query =
      params
      |> Map.take(@filter_keys)
      |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
      |> Map.new()

    {:noreply, push_patch(socket, to: ~p"/management/dispatches/board?#{query}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <:actions>
        <.link
          navigate={~p"/management/dispatches"}
          class="text-button rounded-md border border-hairline bg-surface px-4 py-2 text-ink hover:bg-canvas-soft"
        >
          配車一覧
        </.link>
        <.link
          navigate={~p"/management/dispatches/new"}
          class="text-button rounded-full bg-primary px-4 py-2 text-on-primary hover:bg-primary-active"
        >
          配車を登録
        </.link>
      </:actions>

      <div class="space-y-6">
        <div class="flex flex-col gap-3 rounded-lg border border-hairline bg-surface p-4 lg:flex-row lg:items-end">
          <BoardComponents.date_nav date={@date} path={&board_path(&1, @axis, @office_id)} />

          <form
            id="board-filter"
            phx-change="filter"
            class="flex flex-col gap-3 lg:flex-row lg:items-end"
          >
            <div class="lg:w-44">
              <label class="text-eyebrow text-ink-muted" for="board-date">日付</label>
              <input
                type="date"
                id="board-date"
                name="date"
                value={Date.to_iso8601(@date)}
                class="text-body-sm mt-1 w-full rounded-xs border border-hairline bg-surface px-2 py-2 text-ink"
              />
            </div>
            <.filter_select
              name="axis"
              label="表示する行"
              value={@axis}
              options={[{"車両", "vehicle"}, {"ドライバー", "driver"}]}
              prompt="車両"
            />
            <.filter_select
              :if={Scope.admin?(@current_scope)}
              name="office_id"
              label="拠点"
              value={@office_id}
              options={@offices}
            />
          </form>
        </div>

        <h2 class="text-title" id="board-date-title">{format_heading(@date)}</h2>

        <BoardComponents.board
          board={@board}
          now={@now}
          row_label={row_label(@axis)}
          show_path={&~p"/management/dispatches/#{&1}"}
        />
      </div>
    </Layouts.app>
    """
  end

  defp board_path(date, axis, office_id) do
    query =
      %{"date" => Date.to_iso8601(date), "axis" => to_string(axis), "office_id" => office_id}
      |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
      |> Map.new()

    ~p"/management/dispatches/board?#{query}"
  end

  defp rows(scope, :vehicle, office_id) do
    scope
    |> Vehicles.all_selectable_vehicles()
    |> in_office(office_id)
    |> Enum.map(&%{id: &1.id, name: &1.plate_number})
  end

  defp rows(scope, :driver, office_id) do
    scope
    |> Drivers.all_selectable_drivers()
    |> in_office(office_id)
    |> Enum.map(&%{id: &1.id, name: &1.name})
  end

  defp in_office(records, nil), do: records
  defp in_office(records, office_id), do: Enum.filter(records, &(&1.office_id == office_id))

  defp row_label(:vehicle), do: "車両"
  defp row_label(:driver), do: "ドライバー"

  defp parse_axis("driver"), do: :driver
  defp parse_axis(_axis), do: :vehicle

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _error -> ConvertDatetime.today()
    end
  end

  defp parse_date(_value), do: ConvertDatetime.today()

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp format_heading(date) do
    weekday = Enum.at(~w(月 火 水 木 金 土 日), Date.day_of_week(date) - 1)
    "#{date.year}年#{date.month}月#{date.day}日（#{weekday}）"
  end

  defp office_options(scope) do
    if Scope.admin?(scope) do
      Enum.map(Offices.all_offices(), &{&1.name, &1.id})
    else
      []
    end
  end
end
