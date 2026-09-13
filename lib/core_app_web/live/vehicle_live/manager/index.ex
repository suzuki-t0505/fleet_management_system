defmodule CoreAppWeb.VehicleLive.Manager.Index do
  @moduledoc false
  use CoreAppWeb, :live_view

  alias CoreApp.Accounts.Scope
  alias CoreApp.Offices
  alias CoreApp.Vehicles

  alias CoreAppWeb.VehicleLive.Labels

  @filter_keys ~w(q office_id status vehicle_class page)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "車両台帳")
     |> assign(offices: office_options(socket.assigns.current_scope))}
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

    {:noreply, push_patch(socket, to: ~p"/management/vehicles?#{filters}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <:actions>
        <.link
          navigate={~p"/management/vehicles/new"}
          class="text-button rounded-full bg-primary px-4 py-2 text-on-primary hover:bg-primary-active"
        >
          車両を登録
        </.link>
      </:actions>

      <div class="space-y-6">
        <.search_bar params={@filters} placeholder="車両番号・車名で検索">
          <:filters>
            <.filter_select
              :if={Scope.admin?(@current_scope)}
              name="office_id"
              label="拠点"
              value={@filters["office_id"]}
              options={@offices}
            />
            <.filter_select
              name="status"
              label="ステータス"
              value={@filters["status"]}
              options={Labels.status_options()}
              prompt="廃車以外"
            />
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
        >
          <:actions>
            <.link
              navigate={~p"/management/vehicles/new"}
              class="text-button rounded-full bg-primary px-4 py-2 text-on-primary hover:bg-primary-active"
            >
              車両を登録
            </.link>
          </:actions>
        </.empty_state>

        <div :if={@page.entries != []} class="space-y-4">
          <.data_table
            id="vehicles"
            rows={@page.entries}
            row_id={&"vehicle-#{&1.id}"}
            row_click={&JS.navigate(~p"/management/vehicles/#{&1}")}
          >
            <:col :let={vehicle} label="車両番号">{vehicle.plate_number}</:col>
            <:col :let={vehicle} label="車名">
              {vehicle.model_name}
              <span class="text-caption text-ink-muted">（{vehicle.maker}）</span>
            </:col>
            <:col :let={vehicle} label="車種区分">
              {Labels.vehicle_class(vehicle.vehicle_class)}
            </:col>
            <:col :let={vehicle} :if={Scope.admin?(@current_scope)} label="拠点">
              {vehicle.office.name}
            </:col>
            <:col :let={vehicle} label="ステータス">
              <.status_badge status={vehicle.status} />
            </:col>
            <:col :let={vehicle} label="車検満了日">
              <.deadline_badge date={vehicle.inspection_expires_on} />
            </:col>
          </.data_table>

          <.pagination page={@page} path={&page_path(@filters, &1)} />
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp page_path(filters, page) do
    ~p"/management/vehicles?#{Map.put(filters, "page", page)}"
  end

  defp office_options(scope) do
    if Scope.admin?(scope) do
      Enum.map(Offices.all_offices(), &{&1.name, &1.id})
    else
      []
    end
  end
end
