defmodule CoreAppWeb.ReportLive.Manager.Index do
  @moduledoc false
  use CoreAppWeb, :live_view

  alias CoreApp.Accounts.Scope
  alias CoreApp.Offices
  alias CoreApp.Reports

  alias CoreAppWeb.ExportColumns
  alias CoreAppWeb.IncidentLive.Labels, as: IncidentLabels
  alias CoreAppWeb.MaintenanceLive.Labels, as: MaintenanceLabels

  @filter_keys ~w(report from to axis office_id page)

  @reports [
    {"走行距離集計", "distance"},
    {"燃費集計", "fuel"},
    {"整備費集計", "maintenance_cost"},
    {"事故・ヒヤリ集計", "incident"}
  ]

  @axes %{
    "distance" => [{"車両", "vehicle"}, {"運転者", "driver"}, {"拠点", "office"}],
    "maintenance_cost" => [{"車両", "vehicle"}, {"拠点", "office"}]
  }

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "集計")
     |> assign(reports: @reports)
     |> assign(offices: office_options(socket.assigns.current_scope))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = Map.take(params, @filter_keys)
    report = report_of(filters)

    {:noreply,
     socket
     |> assign(filters: filters)
     |> assign(report: report)
     |> assign(axis_options: Map.get(@axes, to_string(report), []))
     |> assign(page: load(socket.assigns.current_scope, report, filters))}
  end

  @impl true
  def handle_event("filter", params, socket) do
    {:noreply, push_patch(socket, to: ~p"/management/reports?#{clean(params)}")}
  end

  defp load(scope, :distance, filters), do: Reports.distance_report(scope, filters)
  defp load(scope, :fuel, filters), do: Reports.fuel_report(scope, filters)

  defp load(scope, :maintenance_cost, filters),
    do: Reports.maintenance_cost_report(scope, filters)

  defp load(scope, :incident, filters), do: Reports.incident_report(scope, filters)

  defp report_of(filters) do
    Enum.find(Reports.report_types(), :distance, &(to_string(&1) == filters["report"]))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <:actions>
        <.link
          href={~p"/management/exports/reports/#{@report}?#{@filters}"}
          class="text-button rounded-full bg-primary px-4 py-2 text-on-primary hover:bg-primary-active"
        >
          CSV出力
        </.link>
      </:actions>

      <div class="space-y-6">
        <p class="text-body-sm text-ink-muted">
          集計対象は<strong>承認済みの日報</strong>のみです。月は運行日・実施日・発生日（JST）で区切ります。
        </p>

        <.search_bar params={@filters} placeholder="">
          <:filters>
            <.filter_select
              name="report"
              label="集計"
              value={@filters["report"]}
              options={@reports}
              prompt="走行距離集計"
            />
            <.filter_select
              :if={@axis_options != []}
              name="axis"
              label="集計軸"
              value={@filters["axis"]}
              options={@axis_options}
              prompt="車両"
            />
            <.filter_select
              :if={Scope.admin?(@current_scope)}
              name="office_id"
              label="拠点"
              value={@filters["office_id"]}
              options={@offices}
            />
            <div class="lg:w-40">
              <label class="text-eyebrow text-ink-muted" for="filter-from">開始月</label>
              <input
                type="month"
                id="filter-from"
                name="from"
                value={@filters["from"]}
                class="text-body-sm mt-1 w-full rounded-xs border border-hairline bg-surface px-2 py-2 text-ink"
              />
            </div>
            <div class="lg:w-40">
              <label class="text-eyebrow text-ink-muted" for="filter-to">終了月</label>
              <input
                type="month"
                id="filter-to"
                name="to"
                value={@filters["to"]}
                class="text-body-sm mt-1 w-full rounded-xs border border-hairline bg-surface px-2 py-2 text-ink"
              />
            </div>
          </:filters>
        </.search_bar>

        <.empty_state
          :if={@page.entries == []}
          message="集計対象のデータがありません。"
        />

        <div :if={@page.entries != []} class="space-y-4">
          <.data_table :if={@report == :distance} id="distance-report" rows={@page.entries}>
            <:col :let={row} label="月">{ExportColumns.month(row.month)}</:col>
            <:col :let={row} label="対象">{row.key_name}</:col>
            <:col :let={row} label="走行距離">{row.distance_km} km</:col>
            <:col :let={row} label="稼働日数">{row.operating_days} 日</:col>
            <:col :let={row} label="日報件数">{row.report_count} 件</:col>
          </.data_table>

          <.data_table :if={@report == :fuel} id="fuel-report" rows={@page.entries}>
            <:col :let={row} label="月">{ExportColumns.month(row.month)}</:col>
            <:col :let={row} label="車両">{row.key_name}</:col>
            <:col :let={row} label="走行距離">{row.distance_km} km</:col>
            <:col :let={row} label="給油量">{decimal(row.liters, "L")}</:col>
            <:col :let={row} label="燃費">{decimal(row.km_per_liter, "km/L")}</:col>
            <:col :let={row} label="給油金額">{decimal(row.amount_yen, "円")}</:col>
          </.data_table>

          <.data_table
            :if={@report == :maintenance_cost}
            id="maintenance-cost-report"
            rows={@page.entries}
          >
            <:col :let={row} label="月">{ExportColumns.month(row.month)}</:col>
            <:col :let={row} label="対象">{row.key_name}</:col>
            <:col :let={row} label="区分">{MaintenanceLabels.category(row.category)}</:col>
            <:col :let={row} label="費用">{MaintenanceLabels.cost(row.cost_yen)}</:col>
            <:col :let={row} label="件数">{row.maintenance_count} 件</:col>
          </.data_table>

          <.data_table :if={@report == :incident} id="incident-report" rows={@page.entries}>
            <:col :let={row} label="月">{ExportColumns.month(row.month)}</:col>
            <:col :let={row} label="拠点">{row.key_name}</:col>
            <:col :let={row} label="区分">{IncidentLabels.category(row.category)}</:col>
            <:col :let={row} label="発生件数">{row.total_count} 件</:col>
            <:col :let={row} label="改善報告完了">{row.closed_count} 件</:col>
            <:col :let={row} label="完了率">{percentage(row.completion_rate)}</:col>
          </.data_table>

          <.pagination page={@page} path={&~p"/management/reports?#{Map.put(@filters, "page", &1)}"} />
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp decimal(nil, _unit), do: "-"
  defp decimal(value, unit), do: "#{Decimal.to_string(Decimal.new(value), :normal)} #{unit}"

  defp percentage(nil), do: "-"
  defp percentage(value), do: "#{value} %"

  defp clean(params) do
    params
    |> Map.take(@filter_keys)
    |> Map.delete("page")
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  defp office_options(scope) do
    if Scope.admin?(scope) do
      Enum.map(Offices.all_offices(), &{&1.name, &1.id})
    else
      []
    end
  end
end
