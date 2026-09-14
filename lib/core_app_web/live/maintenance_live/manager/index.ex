defmodule CoreAppWeb.MaintenanceLive.Manager.Index do
  @moduledoc false
  use CoreAppWeb, :live_view

  alias CoreApp.Accounts.Scope
  alias CoreApp.Maintenances
  alias CoreApp.Offices
  alias CoreApp.Vehicles

  alias CoreAppWeb.MaintenanceLive.Labels

  @filter_keys ~w(q from to vehicle_id category office_id page)

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    {:ok,
     socket
     |> assign(page_title: "点検整備記録")
     |> assign(vehicles: vehicle_options(scope))
     |> assign(offices: office_options(scope))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = Map.take(params, @filter_keys)

    {:noreply,
     socket
     |> assign(filters: filters)
     |> assign(page: Maintenances.list_maintenances(socket.assigns.current_scope, filters))}
  end

  @impl true
  def handle_event("filter", params, socket) do
    {:noreply, push_patch(socket, to: ~p"/management/maintenances?#{clean(params)}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <:actions>
        <.link
          navigate={~p"/management/maintenances/new"}
          class="text-button rounded-full bg-primary px-4 py-2 text-on-primary hover:bg-primary-active"
        >
          記録を登録
        </.link>
      </:actions>

      <div class="space-y-6">
        <.search_bar params={@filters} placeholder="車両番号・実施業者で検索">
          <:filters>
            <.filter_select
              name="category"
              label="区分"
              value={@filters["category"]}
              options={Labels.category_options()}
            />
            <.filter_select
              name="vehicle_id"
              label="車両"
              value={@filters["vehicle_id"]}
              options={@vehicles}
            />
            <.filter_select
              :if={Scope.admin?(@current_scope)}
              name="office_id"
              label="拠点"
              value={@filters["office_id"]}
              options={@offices}
            />
            <div class="lg:w-40">
              <label class="text-eyebrow text-ink-muted" for="filter-from">開始日</label>
              <input
                type="date"
                id="filter-from"
                name="from"
                value={@filters["from"]}
                class="text-body-sm mt-1 w-full rounded-xs border border-hairline bg-surface px-2 py-2 text-ink"
              />
            </div>
            <div class="lg:w-40">
              <label class="text-eyebrow text-ink-muted" for="filter-to">終了日</label>
              <input
                type="date"
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
          message="条件に一致する点検整備記録がありません。"
        >
          <:actions>
            <.link
              navigate={~p"/management/maintenances/new"}
              class="text-button rounded-full bg-primary px-4 py-2 text-on-primary hover:bg-primary-active"
            >
              記録を登録
            </.link>
          </:actions>
        </.empty_state>

        <div :if={@page.entries != []} class="space-y-4">
          <.data_table
            id="maintenances"
            rows={@page.entries}
            row_id={&"maintenance-#{&1.id}"}
            row_click={&JS.navigate(~p"/management/maintenances/#{&1}")}
          >
            <:col :let={maintenance} label="実施日">
              {format_date(maintenance.performed_on)}
            </:col>
            <:col :let={maintenance} label="車両">{maintenance.vehicle.plate_number}</:col>
            <:col :let={maintenance} label="区分">{Labels.category(maintenance.category)}</:col>
            <:col :let={maintenance} label="実施業者">{maintenance.vendor}</:col>
            <:col :let={maintenance} label="オドメーター">
              {Labels.odometer(maintenance.odometer)}
            </:col>
            <:col :let={maintenance} label="費用">{Labels.cost(maintenance.cost_yen)}</:col>
            <:col :let={maintenance} :if={Scope.admin?(@current_scope)} label="拠点">
              {maintenance.office.name}
            </:col>
            <:col :let={maintenance} label="次回予定日">
              <.deadline_badge date={maintenance.next_scheduled_on} />
            </:col>
          </.data_table>

          <.pagination
            page={@page}
            path={&~p"/management/maintenances?#{Map.put(@filters, "page", &1)}"}
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
    |> Enum.map(&{"#{&1.plate_number}（#{&1.model_name}）", &1.id})
  end

  defp office_options(scope) do
    if Scope.admin?(scope) do
      Enum.map(Offices.all_offices(), &{&1.name, &1.id})
    else
      []
    end
  end
end
