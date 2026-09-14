defmodule CoreAppWeb.OperationReportLive.Manager.Show do
  @moduledoc false
  use CoreAppWeb, :live_view

  alias CoreApp.OperationReports

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok, socket |> assign(rejecting?: false) |> assign_report(id)}
  end

  @impl true
  def handle_event("approve", _params, socket) do
    case OperationReports.approve_report(socket.assigns.current_scope, socket.assigns.report) do
      {:ok, report} ->
        {:noreply,
         socket
         |> put_flash(:info, "日報を承認しました")
         |> assign_report(report.id)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "承認できませんでした")}
    end
  end

  def handle_event("start_reject", _params, socket) do
    {:noreply, assign(socket, rejecting?: true)}
  end

  def handle_event("cancel_reject", _params, socket) do
    {:noreply, assign(socket, rejecting?: false, reject_error: nil)}
  end

  def handle_event("reject", %{"rejected_reason" => reason}, socket) do
    case OperationReports.reject_report(
           socket.assigns.current_scope,
           socket.assigns.report,
           reason
         ) do
      {:ok, report} ->
        {:noreply,
         socket
         |> put_flash(:info, "日報を差し戻しました")
         |> assign(rejecting?: false, reject_error: nil)
         |> assign_report(report.id)}

      {:error, %Ecto.Changeset{}} ->
        {:noreply, assign(socket, reject_error: "差戻しの理由を入力してください")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "差し戻せませんでした")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <:actions>
        <.link
          :if={@editable?}
          navigate={~p"/management/operation_reports/#{@report}/edit"}
          class="text-button rounded-md border border-hairline bg-surface px-4 py-2 text-ink hover:bg-canvas-soft"
        >
          編集
        </.link>
        <button
          :if={@report.status == :submitted}
          phx-click="start_reject"
          class="text-button rounded-md border border-accent-orange-deep px-4 py-2 text-accent-orange-deep hover:bg-canvas-soft"
        >
          差し戻す
        </button>
        <button
          :if={@report.status == :submitted}
          phx-click="approve"
          data-confirm="この日報を承認します。よろしいですか？"
          class="text-button rounded-full bg-primary px-4 py-2 text-on-primary hover:bg-primary-active"
        >
          承認する
        </button>
      </:actions>

      <div class="space-y-6">
        <.link
          navigate={~p"/management/operation_reports"}
          class="text-body-sm inline-flex items-center gap-1 text-ink-muted hover:text-primary"
        >
          <.icon name="hero-arrow-left" class="size-4" /> 日報一覧へ戻る
        </.link>

        <form
          :if={@rejecting?}
          id="reject-form"
          phx-submit="reject"
          class="rounded-lg border border-accent-orange-deep bg-surface p-4"
        >
          <label class="text-eyebrow text-accent-orange-deep" for="rejected_reason">
            差戻しの理由 *
          </label>
          <textarea
            id="rejected_reason"
            name="rejected_reason"
            rows="3"
            class="text-body-sm mt-2 w-full rounded-xs border border-hairline bg-surface px-3 py-2 text-ink"
            placeholder="修正してほしい内容を具体的に記入してください"
          ></textarea>
          <p :if={@reject_error} class="text-caption mt-1 text-accent-orange-deep">{@reject_error}</p>
          <div class="mt-3 flex gap-2">
            <button
              type="button"
              phx-click="cancel_reject"
              class="text-button rounded-md border border-hairline px-4 py-2 text-ink"
            >
              キャンセル
            </button>
            <button
              type="submit"
              class="text-button rounded-full bg-accent-orange-deep px-4 py-2 text-on-primary"
            >
              差し戻す
            </button>
          </div>
        </form>

        <div :if={@warnings != []} class="rounded-lg border border-accent-orange bg-surface p-4">
          <p class="text-eyebrow text-accent-orange">確認してください</p>
          <ul class="mt-2 space-y-1">
            <li :for={warning <- @warnings} class="text-body-sm text-ink-secondary">{warning}</li>
          </ul>
        </div>

        <div
          :if={@report.status == :rejected}
          class="rounded-lg border border-accent-orange-deep bg-surface p-4"
        >
          <p class="text-eyebrow text-accent-orange-deep">差戻し中</p>
          <p class="text-body-sm mt-2 whitespace-pre-wrap text-ink-secondary">
            {@report.rejected_reason}
          </p>
        </div>

        <.section_card title="運行">
          <:actions>
            <.status_badge status={@report.status} type={:operation_report} />
          </:actions>
          <.definition_list columns={3}>
            <:item label="運行日">{format_date(@report.operation_date)}</:item>
            <:item label="車両">{@report.vehicle.plate_number}（{@report.vehicle.model_name}）</:item>
            <:item label="運転者">{@report.driver.name}</:item>
            <:item label="出発日時">{format_datetime(@report.departed_at)}</:item>
            <:item label="帰着日時">{format_datetime(@report.returned_at)}</:item>
            <:item label="休憩時間">{rest_minutes(@report.rest_minutes)}</:item>
            <:item label="出発時の走行距離計">{@report.start_odometer} km</:item>
            <:item label="帰着時の走行距離計">{@report.end_odometer} km</:item>
            <:item label="走行距離">{@report.distance_km} km</:item>
          </.definition_list>
        </.section_card>

        <.section_card title="給油">
          <p :if={@report.refuelings == []} class="text-body-sm text-ink-muted">給油の記録はありません。</p>
          <ul :if={@report.refuelings != []} class="space-y-3">
            <li :for={refueling <- @report.refuelings} class="rounded-md border border-hairline p-4">
              <.definition_list columns={3}>
                <:item label="給油日時">{format_datetime(refueling.refueled_at)}</:item>
                <:item label="給油量">{refueling.liters} L</:item>
                <:item label="金額">{amount(refueling.amount_yen)}</:item>
              </.definition_list>
            </li>
          </ul>
        </.section_card>

        <.section_card title="その他">
          <.definition_list>
            <:item label="主な行き先">{@report.destination || "-"}</:item>
            <:item label="荷種">{@report.cargo_type || "-"}</:item>
            <:item label="作成者">{@report.created_by_user.name}</:item>
            <:item label="提出日時">{format_datetime(@report.submitted_at)}</:item>
            <:item label="承認者">{approver(@report)}</:item>
            <:item label="承認日時">{format_datetime(@report.approved_at)}</:item>
          </.definition_list>
          <p class="text-eyebrow text-ink-muted mt-4">備考</p>
          <p class="text-body-sm mt-1 whitespace-pre-wrap text-ink-secondary">
            {@report.note || "-"}
          </p>
        </.section_card>
      </div>
    </Layouts.app>
    """
  end

  defp assign_report(socket, id) do
    scope = socket.assigns.current_scope
    report = OperationReports.get_operation_report!(scope, id)
    changeset = OperationReports.change_operation_report(report, scope)

    socket
    |> assign(report: report)
    |> assign(editable?: OperationReports.editable?(scope, report))
    |> assign(warnings: OperationReports.warnings(scope, changeset))
    |> assign(reject_error: Map.get(socket.assigns, :reject_error))
    |> assign(page_title: "#{format_date(report.operation_date)} の日報")
  end

  defp approver(%{approved_by_user: nil}), do: "-"
  defp approver(%{approved_by_user: user}), do: user.name

  defp rest_minutes(nil), do: "-"
  defp rest_minutes(minutes), do: "#{minutes} 分"

  defp amount(nil), do: "-"
  defp amount(yen), do: "¥#{yen}"
end
