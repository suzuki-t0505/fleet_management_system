defmodule CoreAppWeb.IncidentLive.Manager.Show do
  @moduledoc false
  use CoreAppWeb, :live_view

  alias CoreApp.Accounts.Scope
  alias CoreApp.Attachments
  alias CoreApp.Incidents

  alias CoreAppWeb.IncidentLive.Labels

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    incident = Incidents.get_incident!(socket.assigns.current_scope, id)

    {:ok, assign_incident(socket, incident)}
  end

  @impl true
  def handle_event("start_analysis", _params, socket) do
    socket.assigns.current_scope
    |> Incidents.start_analysis(socket.assigns.incident)
    |> handle_result(socket, "原因分析を開始しました")
  end

  def handle_event("validate", %{"incident" => params}, socket) do
    changeset =
      socket.assigns.incident
      |> Incidents.change_countermeasure(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: :incident))}
  end

  def handle_event("report_countermeasure", %{"incident" => params}, socket) do
    case Incidents.report_countermeasure(
           socket.assigns.current_scope,
           socket.assigns.incident,
           params
         ) do
      {:ok, incident} ->
        {:noreply,
         socket
         |> assign_incident(incident)
         |> put_flash(:info, "改善策を登録しました")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: :incident))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, error_message(reason))}
    end
  end

  def handle_event("approve", _params, socket) do
    socket.assigns.current_scope
    |> Incidents.approve_incident(socket.assigns.incident)
    |> handle_result(socket, "改善報告を承認しました")
  end

  def handle_event("reject", _params, socket) do
    socket.assigns.current_scope
    |> Incidents.reject_incident(socket.assigns.incident)
    |> handle_result(socket, "分析中に差し戻しました")
  end

  def handle_event("toggle_share", _params, socket) do
    incident = socket.assigns.incident

    socket.assigns.current_scope
    |> Incidents.share_incident(incident, !incident.shared_company_wide)
    |> handle_result(socket, share_message(!incident.shared_company_wide))
  end

  defp handle_result({:ok, incident}, socket, message) do
    {:noreply,
     socket
     |> assign_incident(incident)
     |> put_flash(:info, message)}
  end

  defp handle_result({:error, reason}, socket, _message) do
    {:noreply, put_flash(socket, :error, error_message(reason))}
  end

  defp share_message(true), do: "全社共有を開始しました"
  defp share_message(false), do: "全社共有を解除しました"

  defp error_message(:reporter), do: "報告者本人は承認・差戻しができません"
  defp error_message(:invalid_status), do: "この状態では実行できません"
  defp error_message(:unauthorized), do: "権限がありません"
  defp error_message(%Ecto.Changeset{}), do: "入力内容を確認してください"
  defp error_message(_reason), do: "実行できませんでした"

  defp assign_incident(socket, incident) do
    scope = socket.assigns.current_scope
    incident = Incidents.get_incident!(scope, incident.id)

    socket
    |> assign(incident: incident)
    |> assign(page_title: "#{Labels.category(incident.category)}の記録")
    |> assign(analyzable?: Incidents.analyzable?(scope, incident))
    |> assign(approvable?: Incidents.approvable?(scope, incident))
    |> assign(editable?: Incidents.editable?(scope, incident))
    |> assign(attachments: Attachments.all_attachments_for(:incident, incident.id))
    |> assign(form: to_form(Incidents.change_countermeasure(incident), as: :incident))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <:actions>
        <button
          :if={Scope.admin?(@current_scope)}
          type="button"
          phx-click="toggle_share"
          class="text-button rounded-md border border-hairline bg-surface px-4 py-2 text-ink hover:bg-canvas-soft"
        >
          {share_button_label(@incident.shared_company_wide)}
        </button>
      </:actions>

      <div class="space-y-6">
        <.link
          navigate={~p"/management/incidents"}
          class="text-body-sm inline-flex items-center gap-1 text-ink-muted hover:text-primary"
        >
          <.icon name="hero-arrow-left" class="size-4" /> 一覧へ戻る
        </.link>

        <.section_card title="発生状況">
          <:actions>
            <span :if={@incident.shared_company_wide} class="text-caption text-ink-muted">
              全社共有中
            </span>
            <.status_badge status={@incident.status} type={:incident} />
          </:actions>
          <.definition_list>
            <:item label="発生日時">{format_datetime(@incident.occurred_at)}</:item>
            <:item label="区分">{Labels.category(@incident.category)}</:item>
            <:item label="車両">
              <.link
                navigate={~p"/management/vehicles/#{@incident.vehicle_id}"}
                class="text-primary hover:underline"
              >
                {@incident.vehicle.plate_number}
              </.link>
            </:item>
            <:item label="運転者">{driver_name(@incident)}</:item>
            <:item label="発生場所">{@incident.place}</:item>
            <:item label="天候">{Labels.weather(@incident.weather)}</:item>
            <:item label="拠点">{@incident.office.name}</:item>
            <:item label="警察への届出">
              {Labels.police_reported(@incident.police_reported)}
            </:item>
            <:item label="報告者">{@incident.reported_by_user.name}</:item>
            <:item label="承認者">{approver_name(@incident)}</:item>
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

        <.section_card title="写真・書類">
          <.attachment_list attachments={@attachments} />
        </.section_card>

        <.section_card title="原因分析と改善策">
          <:actions>
            <button
              :if={@incident.status == :reported and @analyzable?}
              type="button"
              phx-click="start_analysis"
              class="text-button rounded-md border border-hairline bg-surface px-4 py-2 text-ink hover:bg-canvas-soft"
            >
              原因分析を開始
            </button>
          </:actions>

          <p :if={!@analyzable?} class="text-body-sm text-ink-muted">
            この記録は編集できません。
          </p>

          <.form
            :if={@analyzable?}
            for={@form}
            id="countermeasure-form"
            phx-change="validate"
            phx-submit="report_countermeasure"
            class="space-y-4"
          >
            <.input field={@form[:direct_cause]} type="textarea" label="直接原因 *" />
            <.input field={@form[:background_factor]} type="textarea" label="背景要因" />
            <.input field={@form[:countermeasure]} type="textarea" label="対策内容 *" />
            <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
              <.input field={@form[:countermeasure_due_on]} type="date" label="対策実施予定日" />
              <.input field={@form[:countermeasure_owner]} type="text" label="実施責任者" />
            </div>

            <div class="flex justify-end">
              <button
                type="submit"
                phx-disable-with="保存中..."
                class="text-button rounded-full bg-primary px-6 py-2 text-on-primary hover:bg-primary-active"
              >
                改善策を登録
              </button>
            </div>
          </.form>
        </.section_card>

        <.section_card :if={@incident.status == :countermeasure_reported} title="承認">
          <p :if={!@approvable?} class="text-body-sm text-ink-muted">
            報告者本人は承認・差戻しができません。他の運行管理者に依頼してください。
          </p>
          <div :if={@approvable?} class="flex flex-col gap-3 sm:flex-row sm:justify-end">
            <button
              type="button"
              phx-click="reject"
              class="text-button rounded-md border border-hairline bg-surface px-4 py-2 text-ink hover:bg-canvas-soft"
            >
              差し戻す
            </button>
            <button
              type="button"
              phx-click="approve"
              class="text-button rounded-full bg-primary px-6 py-2 text-on-primary hover:bg-primary-active"
            >
              承認する
            </button>
          </div>
        </.section_card>
      </div>
    </Layouts.app>
    """
  end

  defp share_button_label(true), do: "全社共有を解除"
  defp share_button_label(false), do: "全社共有する"

  defp driver_name(%{driver: %{name: name}}), do: name
  defp driver_name(_incident), do: "-"

  defp approver_name(%{approved_by_user: %{name: name}}), do: name
  defp approver_name(_incident), do: "-"
end
