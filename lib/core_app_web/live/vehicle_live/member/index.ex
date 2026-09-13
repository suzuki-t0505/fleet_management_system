defmodule CoreAppWeb.VehicleLive.Member.Index do
  @moduledoc false
  use CoreAppWeb, :live_view

  alias CoreApp.Vehicles

  alias CoreAppWeb.VehicleLive.Labels

  @filter_keys ~w(q vehicle_class page)

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "車両")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = Map.take(params, @filter_keys)

    {:noreply,
     socket
     |> assign(filters: filters)
     |> assign(page: Vehicles.list_vehicles(socket.assigns.current_scope, filters))}
  end

  @impl true
  def handle_event("filter", params, socket) do
    filters =
      params
      |> Map.take(@filter_keys)
      |> Map.delete("page")
      |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
      |> Map.new()

    {:noreply, push_patch(socket, to: ~p"/vehicles?#{filters}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <div class="space-y-6">
        <.search_bar params={@filters} placeholder="車両番号・車名で検索">
          <:filters>
            <.filter_select
              name="vehicle_class"
              label="車種区分"
              value={@filters["vehicle_class"]}
              options={Labels.vehicle_class_options()}
            />
          </:filters>
        </.search_bar>

        <.empty_state
          :if={@page.entries == []}
          message="条件に一致する車両がありません。"
        />

        <div :if={@page.entries != []} class="space-y-4">
          <.data_table
            id="vehicles"
            rows={@page.entries}
            row_id={&"vehicle-#{&1.id}"}
            row_click={&JS.navigate(~p"/vehicles/#{&1}")}
          >
            <:col :let={vehicle} label="車両番号">{vehicle.plate_number}</:col>
            <:col :let={vehicle} label="車名">
              {vehicle.model_name}
              <span class="text-caption text-ink-muted">（{vehicle.maker}）</span>
            </:col>
            <:col :let={vehicle} label="車種区分">
              {Labels.vehicle_class(vehicle.vehicle_class)}
            </:col>
            <:col :let={vehicle} label="ステータス">
              <.status_badge status={vehicle.status} />
            </:col>
          </.data_table>

          <.pagination page={@page} path={&~p"/vehicles?#{Map.put(@filters, "page", &1)}"} />
        </div>
      </div>
    </Layouts.app>
    """
  end
end
