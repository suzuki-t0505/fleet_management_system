defmodule CoreAppWeb.OperationReportLive.Member.Show do
  @moduledoc false
  use CoreAppWeb, :live_view

  alias CoreApp.OperationReports

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope
    report = OperationReports.get_operation_report!(scope, id)

    {:ok,
     socket
     |> assign(report: report)
     |> assign(editable?: OperationReports.editable?(scope, report))
     |> assign(page_title: "#{format_date(report.operation_date)} の日報")}
  end

  @impl true
  def handle_event("submit", _params, socket) do
    case OperationReports.submit_report(socket.assigns.current_scope, socket.assigns.report) do
      {:ok, report} ->
        {:noreply,
         socket
         |> put_flash(:info, "日報を提出しました")
         |> assign(report: report)
         |> assign(editable?: false)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "日報を提出できませんでした")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <:actions>
        <.link
          :if={@editable?}
          navigate={~p"/operation_reports/#{@report}/edit"}
          class="text-button rounded-md border border-hairline bg-surface px-4 py-2 text-ink hover:bg-canvas-soft"
        >
          編集
        </.link>
        <button
          :if={@editable? && @report.status in [:draft, :rejected]}
          phx-click="submit"
          data-confirm="この内容で提出します。よろしいですか？"
          class="text-button rounded-full bg-primary px-4 py-2 text-on-primary hover:bg-primary-active"
        >
          提出する
        </button>
      </:actions>

      <div class="mx-auto max-w-2xl space-y-6">
        <.link
          navigate={~p"/operation_reports"}
          class="text-body-sm inline-flex items-center gap-1 text-ink-muted hover:text-primary"
        >
          <.icon name="hero-arrow-left" class="size-4" /> 日報一覧へ戻る
        </.link>

        <div
          :if={@report.status == :rejected}
          class="rounded-lg border border-accent-orange-deep bg-surface p-4"
        >
          <p class="text-eyebrow text-accent-orange-deep">差し戻されました</p>
          <p class="text-body-sm mt-2 whitespace-pre-wrap text-ink-secondary">
            {@report.rejected_reason}
          </p>
        </div>

        <.section_card title="運行">
          <:actions>
            <.status_badge status={@report.status} type={:operation_report} />
          </:actions>
          <.definition_list>
            <:item label="運行日">{format_date(@report.operation_date)}</:item>
            <:item label="車両">
              {@report.vehicle.plate_number}（{@report.vehicle.model_name}）
            </:item>
            <:item label="運転者">{@report.driver.name}</:item>
            <:item label="走行距離">{@report.distance_km} km</:item>
          </.definition_list>
        </.section_card>

        <.section_card title="出発・帰着">
          <.definition_list>
            <:item label="出発日時">{format_datetime(@report.departed_at)}</:item>
            <:item label="帰着日時">{format_datetime(@report.returned_at)}</:item>
            <:item label="出発時の走行距離計">{@report.start_odometer} km</:item>
            <:item label="帰着時の走行距離計">{@report.end_odometer} km</:item>
            <:item label="休憩時間">{rest_minutes(@report.rest_minutes)}</:item>
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

  defp rest_minutes(nil), do: "-"
  defp rest_minutes(minutes), do: "#{minutes} 分"

  defp amount(nil), do: "-"
  defp amount(yen), do: "¥#{yen}"
end
