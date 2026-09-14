defmodule CoreAppWeb.IncidentLive.Member.Show do
  @moduledoc false
  use CoreAppWeb, :live_view

  alias CoreApp.Attachments
  alias CoreApp.Incidents

  alias CoreAppWeb.IncidentLive.Labels

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope
    incident = Incidents.get_incident!(scope, id)

    {:ok,
     socket
     |> assign(incident: incident)
     |> assign(page_title: "#{Labels.category(incident.category)}の記録")
     |> assign(anonymize?: Incidents.anonymize?(scope, incident))
     |> assign(editable?: Incidents.editable?(scope, incident))
     |> assign(attachments: Attachments.all_attachments_for(:incident, incident.id))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <:actions>
        <.link
          :if={@editable?}
          navigate={~p"/incidents/#{@incident}/edit"}
          class="text-button rounded-full bg-primary px-4 py-2 text-on-primary hover:bg-primary-active"
        >
          編集
        </.link>
      </:actions>

      <div class="mx-auto max-w-2xl space-y-6">
        <.link
          navigate={~p"/incidents"}
          class="text-body-sm inline-flex items-center gap-1 text-ink-muted hover:text-primary"
        >
          <.icon name="hero-arrow-left" class="size-4" /> 一覧へ戻る
        </.link>

        <.section_card title="発生状況">
          <:actions>
            <.status_badge status={@incident.status} type={:incident} />
          </:actions>
          <.definition_list>
            <:item label="発生日時">{format_datetime(@incident.occurred_at)}</:item>
            <:item label="区分">{Labels.category(@incident.category)}</:item>
            <:item label="車両">{@incident.vehicle.plate_number}</:item>
            <:item label="運転者">
              {Labels.person_name(driver_name(@incident), @anonymize?)}
            </:item>
            <:item label="発生場所">{@incident.place}</:item>
            <:item label="天候">{Labels.weather(@incident.weather)}</:item>
            <:item label="警察への届出">
              {Labels.police_reported(@incident.police_reported)}
            </:item>
            <:item label="報告者">
              {Labels.person_name(@incident.reported_by_user.name, @anonymize?)}
            </:item>
          </.definition_list>

          <p class="text-body-sm mt-4 whitespace-pre-wrap text-ink-secondary">
            {@incident.description}
          </p>
        </.section_card>

        <.section_card title="相手方・被害">
          <.definition_list columns={1}>
            <:item label="相手方の概要">{@incident.counterpart || "-"}</:item>
            <:item label="被害・損害の概要">{@incident.damage || "-"}</:item>
          </.definition_list>
        </.section_card>

        <.section_card title="改善の状況">
          <p :if={@incident.status == :reported} class="text-body-sm text-ink-muted">
            運行管理者が原因分析を行います。報告ありがとうございました。
          </p>
          <.definition_list :if={@incident.status != :reported} columns={1}>
            <:item label="直接原因">{@incident.direct_cause || "-"}</:item>
            <:item label="背景要因">{@incident.background_factor || "-"}</:item>
            <:item label="対策内容">{@incident.countermeasure || "-"}</:item>
            <:item label="実施予定日">{format_date(@incident.countermeasure_due_on)}</:item>
            <:item label="実施責任者">{@incident.countermeasure_owner || "-"}</:item>
          </.definition_list>
        </.section_card>

        <.section_card title="写真・書類">
          <.attachment_list attachments={@attachments} />
        </.section_card>
      </div>
    </Layouts.app>
    """
  end

  defp driver_name(%{driver: %{name: name}}), do: name
  defp driver_name(_incident), do: nil
end
