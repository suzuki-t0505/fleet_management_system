defmodule CoreAppWeb.DispatchLive.Manager.Index do
  @moduledoc false
  use CoreAppWeb, :live_view

  alias CoreApp.Accounts.Scope
  alias CoreApp.Dispatches
  alias CoreApp.Dispatches.Dispatch
  alias CoreApp.Drivers
  alias CoreApp.Offices
  alias CoreApp.Shippers
  alias CoreApp.Vehicles

  alias CoreAppWeb.DispatchLive.Labels

  @filter_keys ~w(q office_id shipper_id vehicle_id driver_id from to page)

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    {:ok,
     socket
     |> assign(page_title: "配車")
     |> assign(offices: office_options(scope))
     |> assign(shippers: Enum.map(Shippers.all_selectable_shippers(scope), &{&1.name, &1.id}))
     |> assign(vehicles: vehicle_options(scope))
     |> assign(drivers: Enum.map(Drivers.all_selectable_drivers(scope), &{&1.name, &1.id}))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = Map.take(params, @filter_keys)

    {:noreply,
     socket
     |> assign(filters: filters)
     |> assign(page: Dispatches.list_dispatches(socket.assigns.current_scope, filters))}
  end

  @impl true
  def handle_event("filter", params, socket) do
    filters =
      params
      |> Map.take(@filter_keys)
      |> Map.delete("page")
      |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
      |> Map.new()

    {:noreply, push_patch(socket, to: ~p"/management/dispatches?#{filters}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <:actions>
        <.link
          navigate={~p"/management/dispatches/new"}
          class="text-button rounded-full bg-primary px-4 py-2 text-on-primary hover:bg-primary-active"
        >
          配車を登録
        </.link>
        <.link
          navigate={~p"/management/dispatches/board"}
          class="text-button rounded-md border border-hairline bg-surface px-4 py-2 text-ink hover:bg-canvas-soft"
        >
          配車表
        </.link>
        <.link
          href={~p"/management/exports/dispatches?#{@filters}"}
          class="text-button rounded-md border border-hairline bg-surface px-4 py-2 text-ink hover:bg-canvas-soft"
        >
          CSV出力
        </.link>
      </:actions>

      <div class="space-y-6">
        <.search_bar params={@filters} placeholder="タイトル・荷主・配送先で検索">
          <:filters>
            <.filter_select
              :if={Scope.admin?(@current_scope)}
              name="office_id"
              label="拠点"
              value={@filters["office_id"]}
              options={@offices}
            />
            <.filter_select
              name="shipper_id"
              label="荷主"
              value={@filters["shipper_id"]}
              options={@shippers}
            />
            <.filter_select
              name="vehicle_id"
              label="車両"
              value={@filters["vehicle_id"]}
              options={@vehicles}
            />
            <.filter_select
              name="driver_id"
              label="ドライバー"
              value={@filters["driver_id"]}
              options={@drivers}
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
          message="条件に一致する配車がありません。"
        >
          <:actions>
            <.link
              navigate={~p"/management/dispatches/new"}
              class="text-button rounded-full bg-primary px-4 py-2 text-on-primary hover:bg-primary-active"
            >
              配車を登録
            </.link>
          </:actions>
        </.empty_state>

        <div :if={@page.entries != []} class="space-y-4">
          <.data_table
            id="dispatches"
            rows={@page.entries}
            row_id={&"dispatch-#{&1.id}"}
            row_click={&JS.navigate(~p"/management/dispatches/#{&1}")}
          >
            <:col :let={dispatch} label="配送日時">
              {format_datetime(dispatch.started_at)}
              <span class="text-caption text-ink-muted">〜 {format_datetime(dispatch.ended_at)}</span>
            </:col>
            <:col :let={dispatch} label="タイトル">{dispatch.title}</:col>
            <:col :let={dispatch} label="荷主">{dispatch.shipper.name}</:col>
            <:col :let={dispatch} label="車両">{dispatch.vehicle.plate_number}</:col>
            <:col :let={dispatch} label="ドライバー">{dispatch.driver.name}</:col>
            <:col :let={dispatch} :if={Scope.admin?(@current_scope)} label="拠点">
              {dispatch.office.name}
            </:col>
            <:col :let={dispatch} label="料金方式">
              {Labels.pricing_type(dispatch.pricing_type)}
            </:col>
            <:col :let={dispatch} label="受取金額">
              {Labels.yen(Dispatch.total_amount_yen(dispatch))}
            </:col>
          </.data_table>

          <.pagination page={@page} path={&page_path(@filters, &1)} />
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp page_path(filters, page) do
    ~p"/management/dispatches?#{Map.put(filters, "page", page)}"
  end

  defp office_options(scope) do
    if Scope.admin?(scope) do
      Enum.map(Offices.all_offices(), &{&1.name, &1.id})
    else
      []
    end
  end

  defp vehicle_options(scope) do
    scope
    |> Vehicles.all_selectable_vehicles()
    |> Enum.map(&{&1.plate_number, &1.id})
  end
end
