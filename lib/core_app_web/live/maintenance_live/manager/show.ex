defmodule CoreAppWeb.MaintenanceLive.Manager.Show do
  @moduledoc false
  use CoreAppWeb, :live_view

  alias CoreApp.Maintenances

  alias CoreAppWeb.MaintenanceLive.Labels

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    maintenance = Maintenances.get_maintenance!(socket.assigns.current_scope, id)

    {:ok,
     socket
     |> assign(maintenance: maintenance)
     |> assign(page_title: "#{maintenance.vehicle.plate_number} の点検整備記録")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <:actions>
        <.link
          navigate={~p"/management/maintenances/#{@maintenance}/edit"}
          class="text-button rounded-full bg-primary px-4 py-2 text-on-primary hover:bg-primary-active"
        >
          編集
        </.link>
      </:actions>

      <div class="space-y-6">
        <.link
          navigate={~p"/management/maintenances"}
          class="text-body-sm inline-flex items-center gap-1 text-ink-muted hover:text-primary"
        >
          <.icon name="hero-arrow-left" class="size-4" /> 点検整備記録の一覧へ戻る
        </.link>

        <.section_card title="実施内容">
          <.definition_list>
            <:item label="実施日">{format_date(@maintenance.performed_on)}</:item>
            <:item label="区分">{Labels.category(@maintenance.category)}</:item>
            <:item label="車両">
              <.link
                navigate={~p"/management/vehicles/#{@maintenance.vehicle_id}"}
                class="text-primary hover:underline"
              >
                {@maintenance.vehicle.plate_number}
              </.link>
            </:item>
            <:item label="拠点">{@maintenance.office.name}</:item>
            <:item label="オドメーター">{Labels.odometer(@maintenance.odometer)}</:item>
            <:item label="実施業者">{@maintenance.vendor}</:item>
            <:item label="費用">{Labels.cost(@maintenance.cost_yen)}</:item>
            <:item label="次回予定日">
              <.deadline_badge date={@maintenance.next_scheduled_on} />
            </:item>
          </.definition_list>
        </.section_card>

        <.section_card title="作業内容">
          <p class="text-body-sm whitespace-pre-wrap text-ink-secondary">
            {@maintenance.description || "-"}
          </p>
        </.section_card>

        <.section_card title="登録情報">
          <.definition_list>
            <:item label="登録者">{@maintenance.created_by_user.name}</:item>
            <:item label="登録日時">{format_datetime(@maintenance.inserted_at)}</:item>
          </.definition_list>
        </.section_card>
      </div>
    </Layouts.app>
    """
  end
end
