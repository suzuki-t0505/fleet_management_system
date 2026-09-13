defmodule CoreAppWeb.VehicleLive.Member.Show do
  @moduledoc false
  use CoreAppWeb, :live_view

  alias CoreApp.Vehicles

  alias CoreAppWeb.VehicleLive.Labels

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    vehicle = Vehicles.get_vehicle!(socket.assigns.current_scope, id)

    {:ok,
     socket
     |> assign(vehicle: vehicle)
     |> assign(page_title: vehicle.plate_number)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <div class="space-y-6">
        <.link
          navigate={~p"/vehicles"}
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
            <:item label="車名">{@vehicle.model_name}</:item>
            <:item label="メーカー">{@vehicle.maker}</:item>
            <:item label="車種区分">{Labels.vehicle_class(@vehicle.vehicle_class)}</:item>
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
            <:item label="次回3ヶ月点検">
              <.deadline_badge date={@vehicle.next_periodic_3m_on} />
            </:item>
            <:item label="次回12ヶ月点検">
              <.deadline_badge date={@vehicle.next_periodic_12m_on} />
            </:item>
          </.definition_list>
        </.section_card>
      </div>
    </Layouts.app>
    """
  end
end
