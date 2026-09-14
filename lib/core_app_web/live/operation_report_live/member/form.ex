defmodule CoreAppWeb.OperationReportLive.Member.Form do
  @moduledoc false
  use CoreAppWeb, :live_view

  alias CoreApp.Accounts.Scope
  alias CoreApp.Drivers
  alias CoreApp.OperationReports
  alias CoreApp.OperationReports.OperationReport
  alias CoreApp.Utils.ConvertDatetime
  alias CoreApp.Vehicles

  @impl true
  def mount(params, _session, socket) do
    scope = socket.assigns.current_scope

    {:ok,
     socket
     |> assign(vehicles: vehicle_options(scope))
     |> assign(drivers: driver_options(scope))
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    scope = socket.assigns.current_scope
    today = ConvertDatetime.today()

    report = %OperationReport{operation_date: today, driver_id: scope.driver_id}

    socket
    |> assign(page_title: "日報を作成")
    |> assign(report: report)
    |> assign_form(OperationReports.change_operation_report(report, scope))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    scope = socket.assigns.current_scope
    report = OperationReports.get_operation_report!(scope, id)

    if OperationReports.editable?(scope, report) do
      socket
      |> assign(page_title: "日報を編集")
      |> assign(report: report)
      |> assign_form(OperationReports.change_operation_report(report, scope))
    else
      socket
      |> put_flash(:error, "この日報は編集できません")
      |> push_navigate(to: ~p"/operation_reports/#{report}")
    end
  end

  @impl true
  def handle_event("validate", %{"operation_report" => params}, socket) do
    {:noreply, assign_form(socket, changeset(socket, params, :validate))}
  end

  # 「下書き保存」と「提出する」を同じフォームの submit で受け取り、押されたボタンで分岐する
  def handle_event("save", %{"operation_report" => params} = event, socket) do
    save(socket, params, submit?: event["action"] == "submit")
  end

  defp save(socket, params, submit?: submit?) do
    scope = socket.assigns.current_scope

    result =
      case socket.assigns.live_action do
        :new -> OperationReports.create_operation_report(scope, params)
        :edit -> OperationReports.update_operation_report(scope, socket.assigns.report, params)
      end

    case result do
      {:ok, report} -> after_save(socket, scope, report, submit?)
      {:error, changeset} -> {:noreply, assign_form(socket, changeset)}
    end
  end

  defp after_save(socket, scope, report, true) do
    case OperationReports.submit_report(scope, report) do
      {:ok, report} ->
        {:noreply,
         socket
         |> put_flash(:info, "日報を提出しました")
         |> push_navigate(to: ~p"/operation_reports/#{report}")}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "日報を提出できませんでした。内容を確認してください。")
         |> push_navigate(to: ~p"/operation_reports/#{report}")}
    end
  end

  defp after_save(socket, _scope, report, false) do
    {:noreply,
     socket
     |> put_flash(:info, "日報を下書き保存しました")
     |> push_navigate(to: ~p"/operation_reports/#{report}")}
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
        class="mx-auto max-w-2xl space-y-6"
      >
        <div :if={@warnings != []} class="rounded-lg border border-accent-orange bg-surface p-4">
          <p class="text-eyebrow text-accent-orange">確認してください</p>
          <ul class="mt-2 space-y-1">
            <li :for={warning <- @warnings} class="text-body-sm text-ink-secondary">{warning}</li>
          </ul>
        </div>

        <.section_card title="運行">
          <div class="space-y-4">
            <.input field={@form[:operation_date]} type="date" label="運行日 *" />
            <.input
              field={@form[:vehicle_id]}
              type="select"
              label="車両 *"
              prompt="選択してください"
              options={@vehicles}
            />
            <.input
              :if={!Scope.manager?(@current_scope)}
              field={@form[:driver_id]}
              type="hidden"
              value={@current_scope.driver_id}
            />
            <div :if={!Scope.manager?(@current_scope)}>
              <p class="text-eyebrow text-ink-muted">運転者</p>
              <p class="text-body-sm mt-1 text-ink-secondary">{@current_scope.user.name}</p>
            </div>
            <.input
              :if={Scope.manager?(@current_scope)}
              field={@form[:driver_id]}
              type="select"
              label="運転者 *"
              prompt="選択してください"
              options={@drivers}
            />
          </div>
        </.section_card>

        <.section_card title="出発">
          <div class="space-y-4">
            <.input
              field={@form[:departed_at]}
              type="datetime-local"
              label="出発日時 *"
              value={ConvertDatetime.to_input_value(@form[:departed_at].value)}
            />
            <.input
              field={@form[:start_odometer]}
              type="number"
              label="出発時の走行距離計（km）*"
              inputmode="numeric"
            />
          </div>
        </.section_card>

        <.section_card title="帰着">
          <div class="space-y-4">
            <.input
              field={@form[:returned_at]}
              type="datetime-local"
              label="帰着日時 *"
              value={ConvertDatetime.to_input_value(@form[:returned_at].value)}
            />
            <.input
              field={@form[:end_odometer]}
              type="number"
              label="帰着時の走行距離計（km）*"
              inputmode="numeric"
            />

            <div class="rounded-md bg-canvas-soft px-4 py-3">
              <p class="text-eyebrow text-ink-muted">走行距離（自動計算）</p>
              <p class="text-heading-3 mt-1 text-ink">{format_distance(@form)}</p>
            </div>
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

          <p :if={@form[:refuelings].value in [[], nil]} class="text-body-sm text-ink-muted">
            給油した場合は「給油を追加」を押して記録してください。
          </p>

          <div class="space-y-4">
            <.inputs_for :let={refueling} field={@form[:refuelings]}>
              <div class="rounded-md border border-hairline p-4">
                <input
                  type="hidden"
                  name="operation_report[refuelings_sort][]"
                  value={refueling.index}
                />

                <div class="space-y-4">
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
          <div class="space-y-4">
            <.input field={@form[:destination]} type="text" label="主な行き先" />
            <.input field={@form[:cargo_type]} type="text" label="荷種" />
            <.input
              field={@form[:rest_minutes]}
              type="number"
              label="休憩時間（分）"
              inputmode="numeric"
            />
            <.input field={@form[:note]} type="textarea" label="備考" />
          </div>
        </.section_card>

        <div class="flex flex-col gap-3 pb-8 sm:flex-row sm:justify-end">
          <.link
            navigate={~p"/operation_reports"}
            class="text-button rounded-md border border-hairline bg-surface px-4 py-3 text-center text-ink hover:bg-canvas-soft"
          >
            キャンセル
          </.link>
          <button
            type="submit"
            name="action"
            value="draft"
            phx-disable-with="保存中..."
            class="text-button rounded-md border border-hairline bg-surface px-4 py-3 text-ink hover:bg-canvas-soft"
          >
            下書き保存
          </button>
          <button
            type="submit"
            name="action"
            value="submit"
            phx-disable-with="提出中..."
            class="text-button rounded-full bg-primary px-6 py-3 text-on-primary hover:bg-primary-active"
          >
            提出する
          </button>
        </div>
      </.form>
    </Layouts.app>
    """
  end

  defp changeset(socket, params, action) do
    socket.assigns.report
    |> OperationReports.change_operation_report(socket.assigns.current_scope, params)
    |> Map.put(:action, action)
  end

  defp assign_form(socket, changeset) do
    socket
    |> assign(form: to_form(changeset, as: :operation_report))
    |> assign(warnings: OperationReports.warnings(socket.assigns.current_scope, changeset))
  end

  defp format_distance(form) do
    start_odometer = to_integer(form[:start_odometer].value)
    end_odometer = to_integer(form[:end_odometer].value)

    if start_odometer && end_odometer do
      "#{max(end_odometer - start_odometer, 0)} km"
    else
      "-"
    end
  end

  defp to_integer(nil), do: nil
  defp to_integer(value) when is_integer(value), do: value

  defp to_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, _rest} -> parsed
      :error -> nil
    end
  end

  defp to_integer(_value), do: nil

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
