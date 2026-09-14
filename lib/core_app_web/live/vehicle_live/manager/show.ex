defmodule CoreAppWeb.VehicleLive.Manager.Show do
  @moduledoc false
  use CoreAppWeb, :live_view

  alias CoreApp.Incidents
  alias CoreApp.Maintenances
  alias CoreApp.Vehicles

  alias CoreAppWeb.IncidentLive.Labels, as: IncidentLabels
  alias CoreAppWeb.MaintenanceLive.Labels, as: MaintenanceLabels
  alias CoreAppWeb.VehicleLive.Labels

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope
    vehicle = Vehicles.get_vehicle!(scope, id)

    {:ok,
     socket
     |> assign(vehicle: vehicle)
     |> assign(page_title: vehicle.plate_number)
     |> assign(maintenances: Maintenances.all_maintenances_for_vehicle(scope, vehicle.id))
     |> assign(incidents: Incidents.all_incidents_for_vehicle(scope, vehicle.id))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <:actions>
        <.link
          navigate={~p"/management/vehicles/#{@vehicle}/edit"}
          class="text-button rounded-full bg-primary px-4 py-2 text-on-primary hover:bg-primary-active"
        >
          編集
        </.link>
      </:actions>

      <div class="space-y-6">
        <.link
          navigate={~p"/management/vehicles"}
          class="text-body-sm inline-flex items-center gap-1 text-ink-muted hover:text-primary"
        >
          <.icon name="hero-arrow-left" class="size-4" /> 車両一覧へ戻る
        </.link>

        <.section_card title="基本情報">
          <:actions>
            <.status_badge status={@vehicle.status} />
          </:actions>
          <.definition_list>
            <:item label="車両番号">{@vehicle.plate_number}</:item>
            <:item label="車台番号">{@vehicle.vin}</:item>
            <:item label="車名">{@vehicle.model_name}</:item>
            <:item label="メーカー">{@vehicle.maker}</:item>
            <:item label="車種区分">{Labels.vehicle_class(@vehicle.vehicle_class)}</:item>
            <:item label="初度登録年月">{format_date(@vehicle.first_registered_on)}</:item>
            <:item label="拠点">{@vehicle.office.name}</:item>
          </.definition_list>
        </.section_card>

        <.section_card title="期限">
          <.definition_list>
            <:item label="車検満了日">
              <.deadline_badge date={@vehicle.inspection_expires_on} />
            </:item>
            <:item label="自賠責保険満了日">
              <.deadline_badge date={@vehicle.liability_insurance_expires_on} />
            </:item>
            <:item label="任意保険満了日">
              <.deadline_badge date={@vehicle.voluntary_insurance_expires_on} />
            </:item>
            <:item label="次回3ヶ月点検">
              <.deadline_badge date={@vehicle.next_periodic_3m_on} />
            </:item>
            <:item label="次回12ヶ月点検">
              <.deadline_badge date={@vehicle.next_periodic_12m_on} />
            </:item>
          </.definition_list>
        </.section_card>

        <.section_card title="諸元">
          <.definition_list columns={3}>
            <:item label="最大積載量">{format_number(@vehicle.capacity_kg, "kg")}</:item>
            <:item label="車両総重量">{format_number(@vehicle.gross_weight_kg, "kg")}</:item>
            <:item label="乗車定員">{format_number(@vehicle.seating_capacity, "人")}</:item>
            <:item label="燃料種別">{Labels.fuel_type(@vehicle.fuel_type)}</:item>
            <:item label="所有区分">{Labels.ownership(@vehicle.ownership)}</:item>
            <:item label="リース満了日">{format_date(@vehicle.lease_expires_on)}</:item>
            <:item label="最終オドメーター">
              {format_number(@vehicle.latest_odometer, "km")}
            </:item>
          </.definition_list>
        </.section_card>

        <.section_card title="備考">
          <p class="text-body-sm whitespace-pre-wrap text-ink-secondary">
            {@vehicle.note || "-"}
          </p>
        </.section_card>

        <.section_card title="点検整備履歴">
          <:actions>
            <.link
              navigate={~p"/management/maintenances/new?#{%{"vehicle_id" => @vehicle.id}}"}
              class="text-button rounded-full bg-primary px-4 py-2 text-on-primary hover:bg-primary-active"
            >
              記録を登録
            </.link>
          </:actions>

          <p :if={@maintenances == []} class="text-body-sm text-ink-muted">
            点検整備記録がまだありません。
          </p>

          <div :if={@maintenances != []} class="space-y-4">
            <.data_table id="vehicle-maintenances" rows={@maintenances}>
              <:col :let={maintenance} label="実施日">
                {format_date(maintenance.performed_on)}
              </:col>
              <:col :let={maintenance} label="区分">
                {MaintenanceLabels.category(maintenance.category)}
              </:col>
              <:col :let={maintenance} label="実施業者">{maintenance.vendor}</:col>
              <:col :let={maintenance} label="費用">
                {MaintenanceLabels.cost(maintenance.cost_yen)}
              </:col>
            </.data_table>

            <.link
              navigate={~p"/management/maintenances?#{%{"vehicle_id" => @vehicle.id}}"}
              class="text-body-sm text-primary hover:underline"
            >
              この車両の点検整備記録をすべて見る
            </.link>
          </div>
        </.section_card>

        <.section_card title="事故・ヒヤリ履歴">
          <p :if={@incidents == []} class="text-body-sm text-ink-muted">
            事故・ヒヤリの記録はありません。
          </p>

          <div :if={@incidents != []} class="space-y-4">
            <.data_table
              id="vehicle-incidents"
              rows={@incidents}
              row_click={&JS.navigate(~p"/management/incidents/#{&1}")}
            >
              <:col :let={incident} label="発生日時">
                {format_datetime(incident.occurred_at)}
              </:col>
              <:col :let={incident} label="区分">
                {IncidentLabels.category(incident.category)}
              </:col>
              <:col :let={incident} label="場所">{incident.place}</:col>
              <:col :let={incident} label="ステータス">
                <.status_badge status={incident.status} type={:incident} />
              </:col>
            </.data_table>
          </div>
        </.section_card>

        <.section_card title="運行日報">
          <.link
            navigate={~p"/management/operation_reports?#{%{"vehicle_id" => @vehicle.id}}"}
            class="text-body-sm text-primary hover:underline"
          >
            この車両の運行日報を見る
          </.link>
        </.section_card>
      </div>
    </Layouts.app>
    """
  end

  defp format_number(nil, _unit), do: "-"

  defp format_number(number, unit) do
    formatted =
      number
      |> to_string()
      |> String.reverse()
      |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
      |> String.reverse()

    "#{formatted} #{unit}"
  end
end
