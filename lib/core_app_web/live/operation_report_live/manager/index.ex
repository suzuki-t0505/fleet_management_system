defmodule CoreAppWeb.OperationReportLive.Manager.Index do
  @moduledoc false
  use CoreAppWeb, :live_view

  alias CoreApp.Drivers
  alias CoreApp.OperationReports
  alias CoreApp.Utils.ConvertDatetime
  alias CoreApp.Vehicles

  alias CoreAppWeb.OperationReportLive.Labels

  @filter_keys ~w(status from to vehicle_id driver_id office_id page)

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    {:ok,
     socket
     |> assign(page_title: "運行日報")
     |> assign(vehicles: vehicle_options(scope))
     |> assign(drivers: driver_options(scope))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = Map.take(params, @filter_keys)

    {:noreply,
     socket
     |> assign(filters: filters)
     |> assign(
       page: OperationReports.list_operation_reports(socket.assigns.current_scope, filters)
     )}
  end

  @impl true
  def handle_event("filter", params, socket) do
    {:noreply, push_patch(socket, to: ~p"/management/operation_reports?#{clean(params)}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <:actions>
        <.link
          patch={~p"/management/operation_reports?#{%{"status" => "submitted"}}"}
          class="text-button rounded-full bg-primary px-4 py-2 text-on-primary hover:bg-primary-active"
        >
          未承認のみ表示
        </.link>
        <.link
          href={~p"/management/exports/operation_reports?#{@filters}"}
          class="text-button rounded-md border border-hairline bg-surface px-4 py-2 text-ink hover:bg-canvas-soft"
        >
          CSV出力
        </.link>
      </:actions>

      <div class="space-y-6">
        <.search_bar params={@filters} placeholder="">
          <:filters>
            <.filter_select
              name="status"
              label="ステータス"
              value={@filters["status"]}
              options={Labels.status_options()}
            />
            <.filter_select
              name="vehicle_id"
              label="車両"
              value={@filters["vehicle_id"]}
              options={@vehicles}
            />
            <.filter_select
              name="driver_id"
              label="運転者"
              value={@filters["driver_id"]}
              options={@drivers}
            />
            <div class="lg:w-40">
              <label class="text-eyebrow text-ink-muted" for="filter-from">開始日</label>
              <input
                type="date"
                id="filter-from"
                name="from"
                value={@filters["from"] || default_from()}
                class="text-body-sm mt-1 w-full rounded-xs border border-hairline bg-surface px-2 py-2 text-ink"
              />
            </div>
            <div class="lg:w-40">
              <label class="text-eyebrow text-ink-muted" for="filter-to">終了日</label>
              <input
                type="date"
                id="filter-to"
                name="to"
                value={@filters["to"] || default_to()}
                class="text-body-sm mt-1 w-full rounded-xs border border-hairline bg-surface px-2 py-2 text-ink"
              />
            </div>
          </:filters>
        </.search_bar>

        <.empty_state
          :if={@page.entries == []}
          message="条件に一致する日報がありません。"
        />

        <div :if={@page.entries != []} class="space-y-4">
          <.data_table
            id="operation-reports"
            rows={@page.entries}
            row_id={&"report-#{&1.id}"}
            row_click={&JS.navigate(~p"/management/operation_reports/#{&1}")}
          >
            <:col :let={report} label="運行日">{format_date(report.operation_date)}</:col>
            <:col :let={report} label="車両">{report.vehicle.plate_number}</:col>
            <:col :let={report} label="運転者">{report.driver.name}</:col>
            <:col :let={report} label="走行距離">{report.distance_km} km</:col>
            <:col :let={report} label="出発〜帰着">
              {format_time(report.departed_at)}〜{format_time(report.returned_at)}
            </:col>
            <:col :let={report} label="ステータス">
              <.status_badge status={report.status} type={:operation_report} />
            </:col>
          </.data_table>

          <.pagination
            page={@page}
            path={&~p"/management/operation_reports?#{Map.put(@filters, "page", &1)}"}
          />
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp clean(params) do
    params
    |> Map.take(@filter_keys)
    |> Map.delete("page")
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  defp vehicle_options(scope) do
    scope
    |> Vehicles.all_selectable_vehicles()
    |> Enum.map(&{&1.plate_number, &1.id})
  end

  defp driver_options(scope) do
    scope
    |> Drivers.all_selectable_drivers()
    |> Enum.map(&{&1.name, &1.id})
  end

  defp default_from do
    ConvertDatetime.today() |> Date.beginning_of_month() |> Date.to_iso8601()
  end

  defp default_to do
    ConvertDatetime.today() |> Date.end_of_month() |> Date.to_iso8601()
  end

  defp format_time(datetime) do
    jst = ConvertDatetime.to_jst(datetime)

    "#{String.pad_leading(to_string(jst.hour), 2, "0")}:#{String.pad_leading(to_string(jst.minute), 2, "0")}"
  end
end
