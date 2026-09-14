defmodule CoreAppWeb.OperationReportLive.Manager.Form do
  @moduledoc false
  use CoreAppWeb, :live_view

  alias CoreApp.Drivers
  alias CoreApp.OperationReports
  alias CoreApp.Utils.ConvertDatetime
  alias CoreApp.Vehicles

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope
    report = OperationReports.get_operation_report!(scope, id)

    if OperationReports.editable?(scope, report) do
      {:ok,
       socket
       |> assign(page_title: "日報を編集")
       |> assign(report: report)
       |> assign(vehicles: vehicle_options(scope))
       |> assign(drivers: driver_options(scope))
       |> assign_form(OperationReports.change_operation_report(report, scope))}
    else
      {:ok,
       socket
       |> put_flash(:error, "この日報は編集できません")
       |> push_navigate(to: ~p"/management/operation_reports/#{report}")}
    end
  end

  @impl true
  def handle_event("validate", %{"operation_report" => params}, socket) do
    changeset =
      socket.assigns.report
      |> OperationReports.change_operation_report(socket.assigns.current_scope, params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"operation_report" => params}, socket) do
    case OperationReports.update_operation_report(
           socket.assigns.current_scope,
           socket.assigns.report,
           params
         ) do
      {:ok, report} ->
        {:noreply,
         socket
         |> put_flash(:info, "日報を更新しました")
         |> push_navigate(to: ~p"/management/operation_reports/#{report}")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title={@page_title}>
      <.form
        for={@form}
        id="operation-report-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-6"
      >
        <div :if={@warnings != []} class="rounded-lg border border-accent-orange bg-surface p-4">
          <p class="text-eyebrow text-accent-orange">確認してください</p>
          <ul class="mt-2 space-y-1">
            <li :for={warning <- @warnings} class="text-body-sm text-ink-secondary">{warning}</li>
          </ul>
          <p class="text-caption text-ink-muted mt-2">
            内容に問題がなければ、備考に理由を記入して保存できます。
          </p>
        </div>

        <.section_card title="運行">
          <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <.input field={@form[:operation_date]} type="date" label="運行日 *" />
            <.input
              field={@form[:vehicle_id]}
              type="select"
              label="車両 *"
              prompt="選択してください"
              options={@vehicles}
            />
            <.input
              field={@form[:driver_id]}
              type="select"
              label="運転者 *"
              prompt="選択してください"
              options={@drivers}
            />
            <.input field={@form[:rest_minutes]} type="number" label="休憩時間（分）" />
          </div>
        </.section_card>

        <.section_card title="出発・帰着">
          <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <.input
              field={@form[:departed_at]}
              type="datetime-local"
              label="出発日時 *"
              value={ConvertDatetime.to_input_value(@form[:departed_at].value)}
            />
            <.input
              field={@form[:returned_at]}
              type="datetime-local"
              label="帰着日時 *"
              value={ConvertDatetime.to_input_value(@form[:returned_at].value)}
            />
            <.input
              field={@form[:start_odometer]}
              type="number"
              label="出発時の走行距離計（km）*"
            />
            <.input
              field={@form[:end_odometer]}
              type="number"
              label="帰着時の走行距離計（km）*"
            />
          </div>
        </.section_card>

        <.section_card title="給油">
          <:actions>
            <label class="text-button cursor-pointer rounded-md border border-hairline px-3 py-1 text-ink hover:bg-canvas-soft">
              給油を追加
              <input
                type="checkbox"
                name="operation_report[refuelings_sort][]"
                class="hidden"
                value="new"
                phx-click={JS.dispatch("change", to: "#operation-report-form")}
              />
            </label>
          </:actions>

          <div class="space-y-4">
            <.inputs_for :let={refueling} field={@form[:refuelings]}>
              <div class="rounded-md border border-hairline p-4">
                <input
                  type="hidden"
                  name="operation_report[refuelings_sort][]"
                  value={refueling.index}
                />
                <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
                  <.input
                    field={refueling[:refueled_at]}
                    type="datetime-local"
                    label="給油日時 *"
                  />
                  <.input
                    field={refueling[:liters]}
                    type="number"
                    step="0.01"
                    label="給油量（L）*"
                  />
                  <.input field={refueling[:amount_yen]} type="number" label="金額（円）" />
                  <.input
                    field={refueling[:odometer]}
                    type="number"
                    label="給油時の走行距離計（km）"
                  />
                </div>
                <label class="text-caption mt-3 inline-flex cursor-pointer items-center gap-1 text-accent-orange-deep">
                  <input
                    type="checkbox"
                    name="operation_report[refuelings_drop][]"
                    value={refueling.index}
                    class="hidden"
                    phx-click={JS.dispatch("change", to: "#operation-report-form")}
                  />
                  <.icon name="hero-trash" class="size-4" /> この給油を削除
                </label>
              </div>
            </.inputs_for>
          </div>

          <input type="hidden" name="operation_report[refuelings_drop][]" />
        </.section_card>

        <.section_card title="その他">
          <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <.input field={@form[:destination]} type="text" label="主な行き先" />
            <.input field={@form[:cargo_type]} type="text" label="荷種" />
          </div>
          <div class="mt-4">
            <.input field={@form[:note]} type="textarea" label="備考" />
          </div>
        </.section_card>

        <div class="flex flex-col gap-3 sm:flex-row sm:justify-end">
          <.link
            navigate={~p"/management/operation_reports/#{@report}"}
            class="text-button rounded-md border border-hairline bg-surface px-4 py-2 text-center text-ink hover:bg-canvas-soft"
          >
            キャンセル
          </.link>
          <button
            type="submit"
            phx-disable-with="保存中..."
            class="text-button rounded-full bg-primary px-6 py-2 text-on-primary hover:bg-primary-active"
          >
            保存
          </button>
        </div>
      </.form>
    </Layouts.app>
    """
  end

  defp assign_form(socket, changeset) do
    socket
    |> assign(form: to_form(changeset, as: :operation_report))
    |> assign(warnings: OperationReports.warnings(socket.assigns.current_scope, changeset))
  end

  defp vehicle_options(scope) do
    scope
    |> Vehicles.all_selectable_vehicles()
    |> Enum.map(&{"#{&1.plate_number}（#{&1.model_name}）", &1.id})
  end

  defp driver_options(scope) do
    scope
    |> Drivers.all_selectable_drivers()
    |> Enum.map(&{&1.name, &1.id})
  end
end
